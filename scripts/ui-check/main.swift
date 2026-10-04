import Foundation
let now = Date()
func age(_ s: Double) -> String { NotificationRow.age(of: now.addingTimeInterval(-s), at: now) }
assert(age(0) == "Vừa xong")
assert(age(59) == "Vừa xong")
assert(age(60) == "1 phút")
assert(age(120) == "2 phút")
assert(age(59 * 60 + 59) == "59 phút")
assert(age(3600) == "1 giờ")
assert(age(7300) == "2 giờ")
assert(age(-500) == "Vừa xong")   // đồng hồ lệch: thời điểm ở tương lai không ra số âm
print("OK: định dạng tuổi thông báo đúng")
