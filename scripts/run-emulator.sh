#!/bin/bash
# CBLREP optimized emulator launcher
# Tuned for: i3-1115G4 (2C/4T), 11GB RAM, Intel UHD G4 (Mesa), KVM
export JAVA_HOME="/opt/android-studio/jbr"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
export ANDROID_EMULATOR_USE_SYSTEM_LIBS=1

AVD="CBLREP_lite"
# 2 cores = leave 2 threads for Gradle/IDE/OS. 4GB RAM: min the image demands.
# host GPU = Intel Mesa direct rendering (fastest on Tiger Lake).
# swiftshader fallback only for headless/CI.
MODE="${1:-gui}"
case "$MODE" in
  gui)
    exec emulator -avd "$AVD" -accel on -gpu host \
      -memory 4096 -cores 2 -no-audio -no-boot-anim \
      -snapshot default-boot ;;
  cold)
    exec emulator -avd "$AVD" -accel on -gpu host \
      -memory 4096 -cores 2 -no-audio -no-boot-anim \
      -no-snapshot-load ;;
  headless)
    exec emulator -avd "$AVD" -accel on -gpu swiftshader_indirect \
      -memory 4096 -cores 2 -no-audio -no-window -no-boot-anim ;;
  *)
    echo "usage: $0 [gui|cold|headless]"; exit 1 ;;
esac
