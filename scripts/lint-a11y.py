#!/usr/bin/env python3
"""Statická kontrola přístupnosti UI (M12-01): tlačítka jen s ikonou bez popisku pro VoiceOver,
prvky ovládané jen `onTapGesture` bez akce přístupnosti a pohybové animace bez Reduce Motion.
Strom přístupnosti SwiftUI se v `swift test` nesestaví, proto kontrola nad zdroji."""
import glob, re, sys

problems = []
for path in sorted(glob.glob("Sources/MarginUI/**/*.swift", recursive=True) + glob.glob("App/Margin/**/*.swift", recursive=True)):
    if "/Debug/" in path:
        continue
    lines = open(path, encoding="utf-8").read().split("\n")
    for i, line in enumerate(lines):
        window = "\n".join(lines[i:i + 14])
        # 1) Button { … } label: { Icon(…) } without a text, Label or accessibilityLabel nearby.
        if re.search(r"Button\s*(\(action:[^)]*\))?\s*\{", line) and 'Button("' not in line:
            m = re.search(r"label:\s*\{(.*?)\}", window, re.S)
            label = m.group(1) if m else ""
            if "Icon(" in label and "Text(" not in label and "Label" not in label and "accessibilityLabel" not in window:
                problems.append(f"{path}:{i + 1}: tlačítko jen s ikonou bez accessibilityLabel")
        # 2) onTapGesture (single tap) without an accessibility action or button trait nearby.
        if ".onTapGesture" in line and "count: 2" not in line and "dialog = nil" not in line and "capture.close" not in line \
                and "coordinateSpace" not in line:
            around = "\n".join(lines[max(0, i - 12):i + 22])
            if "accessibilityAction" not in around:
                problems.append(f"{path}:{i + 1}: onTapGesture bez accessibilityAction")
        # 3) Movement animations must go through Shell.motion / reduceMotion.
        if re.search(r"withAnimation\(\.(spring|interactiveSpring)", line):
            problems.append(f"{path}:{i + 1}: pružinová animace bez Shell.motion")
        if "func slide(" in "\n".join(lines[max(0, i - 3):i + 1]):
            continue
        if ".transition(.move" in line or ".transition(.slide" in line:
            problems.append(f"{path}:{i + 1}: přechod s pohybem bez Reduce Motion")

for p in problems:
    print(p)
print(f"lint-a11y: {'OK' if not problems else f'{len(problems)} nálezů'}")
sys.exit(1 if problems else 0)
