#!/bin/bash

python3 mirror_ml_server.py \
    --detection_model ./test_data/mobilenet_ssd_v2_face_quant_postprocess_edgetpu.tflite \
    --recognition_model ./test_data/custom_facial_recognition_edgetpu_v2.tflite
