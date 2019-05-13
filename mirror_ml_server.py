#!/usr/bin/env python

import argparse
import platform
import subprocess
import io
import logging
import json
import math
import numpy as np
import socket
import time

from edgetpu.detection.engine import DetectionEngine
from edgetpu.classification.engine import ClassificationEngine
from PIL import Image
from threading import Thread
from mirror_utils import rotate_around_point


UDP_IP = '127.0.0.1'
# TCP_IP = '10.0.0.1'
TCP_IP = UDP_IP

DETECTION_RECEIVE_PORT = 9100
CLASSIFICATION_RECEIVE_PORT = 9101
LOG_RECEIVE_PORT = 9103

SEND_SOCKET_PORT = 9102

DETECTION_IMAGE_BUFFER_SIZE = 66507
CLASSIFICATION_IMAGE_BUFFER_SIZE = 66507  # 7800

face_class_label_ids_to_names = {
    0: 'adi',
    1: 'brent',
    # 2: 'unknown', # required when using our custom models older than v4
}

logger = logging.getLogger(__name__)


def send_with_retry(sendSocket, message):
    #  logger.info('sending', message)
    try:
        sendSocket.send(message.encode('utf-8'))
        # TODO: switch to UDP
        #  receiveSocket.sendto(message.encode('utf-8'), addr)
        #  senderSocket.sendto(message.encode('utf-8'), (UDP_IP, UDP_SEND_PORT))
    except ConnectionResetError:
        logger.info('Socket disconnected...waiting for client')
        sendSocket, addr = sendSocket.accept()

    return sendSocket


def detect_face(engine, sendSocket):
    receiveSocket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiveSocket.bind((UDP_IP, DETECTION_RECEIVE_PORT))

    logger.info('listening on %d ...' % DETECTION_RECEIVE_PORT)

    DETECTION_THRESHOLD = 0.95

    while 1:
        data, _ = receiveSocket.recvfrom(DETECTION_IMAGE_BUFFER_SIZE)

        if (len(data) > 0):
            start_s = time.time()

            try:
                image = Image.open(io.BytesIO(data)).convert('RGB')
            except OSError:
                logger.info('Could not read image')
                continue

            capture_width, capture_height = image.size

            # our camera is sideways, so we need to compensate with clockwise rotation
            image.save('full.jpg', 'JPEG')
            image = image.rotate(-90)

            # see https://coral.withgoogle.com/docs/reference/edgetpu.detection.engine/
            results = engine.DetectWithImage(
                image, threshold=DETECTION_THRESHOLD, keep_aspect_ratio=True, relative_coord=False, top_k=3, resample=Image.BILINEAR)

            # logger.debug('time to detect faces: %d\n' %
            #              (time.time() - start_s) * 1000)

            rotation_origin = (capture_width / 2, capture_height / 2)
            rotation_radians = math.pi / 2

            def map_result(result):
                [x1, y1, x2, y2] = result.bounding_box.flatten().tolist()
                qx1, qy1 = rotate_around_point(
                    (x1, y1), rotation_radians, rotation_origin)
                qx2, qy2 = rotate_around_point(
                    (x2, y2), rotation_radians, rotation_origin)
                # simple ordering would give the top right corner, but we want top left
                return {'box': [qx1, qy2, qx2, qy1]}

            output = list(map(map_result, results))
            logger.debug(output)

            message = json.dumps({'detection': output})
            sendSocket = send_with_retry(sendSocket, message)


def classify_face(engine, sendSocket):
    receiveSocket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiveSocket.bind((UDP_IP, CLASSIFICATION_RECEIVE_PORT))

    CLASSIFICATION_THRESHOLD = 0.6

    while 1:
        data, _ = receiveSocket.recvfrom(DETECTION_IMAGE_BUFFER_SIZE)

        if (len(data) > 0):
            start_s = time.time()

            try:
                image = Image.open(io.BytesIO(data)).convert('RGB')
            except OSError:
                logger.info('could not read image')
                continue

            # our camera is sideways, so we need to compensate with clockwise rotation
            image = image.rotate(-90)

            logger.info('CLASSIFYING')
            image.save('crop.jpg', 'JPEG')
            # see https://coral.withgoogle.com/docs/reference/edgetpu.classification.engine/
            results = engine.ClassifyWithImage(
                image, threshold=CLASSIFICATION_THRESHOLD, top_k=3)

            logger.debug('time to classify face: %d\n' %
                         (time.time() - start_s) * 1000)

            if (len(results) > 0):
                logger.debug(results)

                # sort by confidence, take the highest, return the label
                highest_confidence_result = sorted(
                    results, key=lambda result: result[1], reverse=True)[0]

                [label_id, confidence_float] = highest_confidence_result

                try:
                    message = json.dumps({
                        'classification': face_class_label_ids_to_names[label_id],
                        'confidence': str(confidence_float)
                    })
                    sendSocket = send_with_retry(sendSocket, message)
                except KeyError:
                    logger.error(
                        'classified label "%d" not recognized' % label_id)
            else:
                logger.debug('could not classify image at threshold %f' %
                             CLASSIFICATION_THRESHOLD)


def handle_processing_logs():
    receiveSocket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    receiveSocket.bind((UDP_IP, LOG_RECEIVE_PORT))

    while 1:
        logger.debug('waiting for logs')
        # TODO: plug in the right packet length number
        # right now it's just an arbitrarily large size which *should* get the whole string
        data, _ = receiveSocket.recvfrom(66507)

        if (len(data) > 0):
            try:
                log_bytes = io.BytesIO(data).read()
                log_str = log_bytes.decode('UTF-8')
                logger.info('Processing says: %s' % log_str)
            except OSError:
                logger.info('could not read logs')
                continue


def start_server():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--detection_model', help='Path to the face detection model.', required=True)
    parser.add_argument(
        '--recognition_model', help='Path to the face recognition (image classification) model.', required=True)
    args = parser.parse_args()

    sendSocketRaw = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    # TODO: switch to UDP
    # sendSocket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    # Initialize engines
    detectionEngine = DetectionEngine(args.detection_model)
    recognitionEngine = ClassificationEngine(args.recognition_model)

    logger.info('listening for ML requests on %d ...' % DETECTION_RECEIVE_PORT)

    sendSocketRaw.bind((TCP_IP, SEND_SOCKET_PORT))
    sendSocketRaw.listen(1)
    logger.info('waiting for client to connect...')
    sendSocket, addr = sendSocketRaw.accept()
    # TODO: switch to UDP
    # sendSocket.bind((UDP_IP, UDP_SEND_PORT))

    # at this point, we know the processing client has opened the TCP socket
    logger.info('processing client connected')
    detectionThread = Thread(
        target=detect_face, args=(detectionEngine, sendSocket))
    recognitionThread = Thread(
        target=classify_face, args=(recognitionEngine, sendSocket))
    logReceiverThread = Thread(
        target=handle_processing_logs, args=())

    detectionThread.start()
    recognitionThread.start()
    logReceiverThread.start()


if __name__ == '__main__':
    logger.setLevel(logging.DEBUG)
    consoleHandler = logging.StreamHandler()
    consoleHandler.setLevel(logging.INFO)
    consoleHandler.setFormatter(logging.Formatter(
        '%(asctime)s - %(levelname)s - %(message)s'))
    logger.addHandler(consoleHandler)

    logger.info('running server as main')
    start_server()
