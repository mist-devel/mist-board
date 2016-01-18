#!/bin/bash
avconv -vcodec png -i image.png -vcodec rawvideo -f rawvideo -pix_fmt rgb8 image.raw
srec_cat image.raw -binary -o image.hex -intel

