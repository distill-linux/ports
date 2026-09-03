#!/bin/sh
set -e

echo "================================================="
echo " Running All Distill Package Suite Tests (drop/sink) "
echo "================================================="

echo "\n[1/3] Running ustar streaming, security & .drop tests..."
/home/foggy/distill/tests/test_tar

echo "\n[2/3] Running drop binary package manager tests..."
/home/foggy/distill/tests/test_drop.sh

echo "\n[3/3] Running sink builder & recipe engine tests..."
/home/foggy/distill/tests/test_sink.sh

echo "\n================================================="
echo " All Tests Passed Successfully! "
echo "================================================="
