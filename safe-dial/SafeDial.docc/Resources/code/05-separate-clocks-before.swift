// 적용하지 않는 문제 구조: 두 호출의 시작 시각이 같은 clock에 묶이지 않는다.
audioPlayer.play()
try hapticPlayer.start(atTime: CHHapticTimeImmediate)
