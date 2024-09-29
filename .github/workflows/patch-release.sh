#!/usr/bin/env bash

git config --global user.name 'swift-ci'
git config --global user.email 'swift-ci@users.noreply.github.com'

sed -E -i '' "s#branch: \"(main|release/[0-9]+\.[0-9]+)\"#from: \"$SWIFT_SYNTAX_TAG_NAME\"#" Package.swift
git add Package.swift
git commit -m "Change swift-syntax dependency to $SWIFT_SYNTAX_TAG_NAME"

sed -E -i '' "s#print\(\".*\"\)#print\(\"$TAG_NAME\"\)#" Sources/swift-format/PrintVersion.swift
git add Sources/swift-format/PrintVersion.swift
git commit -m "Change version to $TAG_NAME"
