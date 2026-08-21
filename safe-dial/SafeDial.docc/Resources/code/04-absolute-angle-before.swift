// 적용하지 않는 문제 구조: -π와 +π 사이에서 값이 거의 한 바퀴 뛴다.
let absoluteAngle = atan2(location.y - center.y, location.x - center.x)
game.setAngle(absoluteAngle)
