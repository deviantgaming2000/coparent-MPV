#!/bin/sh
cd "$(dirname "$0")/../.."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun --sdk macosx swiftc "coparent MPV/CustodySchedule.swift" "coparent MPV/CustodyScheduleMapper.swift" tests/custody-mapper/main.swift -o /tmp/custody_mapper_run && /tmp/custody_mapper_run
