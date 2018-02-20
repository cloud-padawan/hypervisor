#!/bin/bash

compress_SWITCH="1"
[[ $compress_SWITCH  ]] && compress_IMG="true" || compress_IMG="false"  

echo "$compress_IMG"
