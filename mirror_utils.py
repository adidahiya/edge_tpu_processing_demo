import math


def rotate_around_point(xy, radians, origin=(0, 0)):
    """
    Rotate a point around a given point.

    see https://gist.github.com/LyleScott/e36e08bfb23b1f87af68c9051f985302
    """
    x, y = xy
    offset_x, offset_y = origin
    adjusted_x = (x - offset_x)
    adjusted_y = (y - offset_y)
    cos_rad = math.cos(radians)
    sin_rad = math.sin(radians)
    qx = offset_x + cos_rad * adjusted_x + sin_rad * adjusted_y
    qy = offset_y + -sin_rad * adjusted_x + cos_rad * adjusted_y

    return qx, qy
