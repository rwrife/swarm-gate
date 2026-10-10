#!/bin/sh
set -e
swiftc -frontend -parse \
  SwarmGate/App/SwarmGateApp.swift \
  SwarmGate/App/DefenseHomeView.swift \
  SwarmGate/App/GameSession.swift \
  SwarmGate/App/PlayableView.swift \
  SwarmGate/App/DefenseWorkspaceLayout.swift \
  SwarmGate/UITests/SwarmGateLaunchTests.swift
echo "SYNTAX PASS"
