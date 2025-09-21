#!/bin/bash
# Simple RunPod test script for activity-aware privacy system

echo "🧪 RunPod Activity-Aware Privacy System Test"
echo "=============================================="

# Test 1: Run the comprehensive Python test
echo ""
echo "🔍 Running comprehensive diagnostic..."
python3 /workspace/scripts/runpod_test.py

echo ""
echo "=============================================="
echo "🚀 Quick Manual Tests:"
echo ""

# Test 2: Simple CLI tests
echo "📋 Testing ignition-privacy commands:"

echo ""
echo "1. Privacy Status:"
ignition-privacy status
echo ""

echo "2. Activity Status:"
ignition-privacy activities
echo ""

echo "3. Debug Health:"
ignition-privacy debug health
echo ""

echo "=============================================="
echo "✅ Test complete! Check output above for any issues."
echo ""
echo "If everything looks good, try:"
echo "  pip install requests"
echo "  ignition-privacy debug activities"
echo ""
echo "Or test model downloads with activity monitoring!"