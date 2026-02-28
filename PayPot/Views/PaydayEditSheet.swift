import SwiftUI

struct PaydayEditSheet: View {
    let prefsStore: PotPreferencesStore

    @Environment(\.dismiss) private var dismiss

    enum ScheduleType: Hashable {
        case fixedDay, lastWorkingDay
        var label: String {
            switch self {
            case .fixedDay:       return "Fixed Day of Month"
            case .lastWorkingDay: return "Last Working Day"
            }
        }
    }

    @State private var enabled: Bool
    @State private var scheduleType: ScheduleType
    @State private var fixedDay: Int
    @State private var fixedDayText: String
    @State private var bacsEarly: Bool

    init(prefsStore: PotPreferencesStore) {
        self.prefsStore = prefsStore
        _enabled = State(initialValue: prefsStore.paydaySchedule != nil)
        switch prefsStore.paydaySchedule {
        case .fixedDay(let d):
            _scheduleType = State(initialValue: .fixedDay)
            _fixedDay = State(initialValue: d)
            _fixedDayText = State(initialValue: String(d))
        case .lastWorkingDay, nil:
            _scheduleType = State(initialValue: .lastWorkingDay)
            _fixedDay = State(initialValue: 1)
            _fixedDayText = State(initialValue: "1")
        }
        _bacsEarly = State(initialValue: prefsStore.bacsEarlyPayment)
    }

    private var currentSchedule: PaydaySchedule {
        switch scheduleType {
        case .fixedDay:       return .fixedDay(fixedDay)
        case .lastWorkingDay: return .lastWorkingDay
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Payday Schedule", isOn: $enabled)
                    .onChange(of: enabled) { _, on in
                        if on {
                            prefsStore.setPaydaySchedule(currentSchedule)
                        } else {
                            prefsStore.setPaydaySchedule(nil)
                            prefsStore.setBacsEarlyPayment(false)
                            bacsEarly = false
                        }
                    }
            }

            if enabled {
                Section("Pay Schedule") {
                    Picker("Type", selection: $scheduleType) {
                        ForEach([ScheduleType.fixedDay, .lastWorkingDay], id: \.self) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: scheduleType) { _, _ in
                        prefsStore.setPaydaySchedule(currentSchedule)
                    }

                    if scheduleType == .fixedDay {
                        HStack {
                            Text("Day of the month")
                            Spacer()
                            TextField("1–31", text: $fixedDayText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 52)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.tint)
                                .fontWeight(.semibold)
                                .onChange(of: fixedDayText) { _, new in
                                    let digits = new.filter(\.isNumber)
                                    if let val = Int(digits) {
                                        let clamped = min(max(1, val), 31)
                                        fixedDay = clamped
                                        if val != clamped { fixedDayText = String(clamped) }
                                        prefsStore.setPaydaySchedule(.fixedDay(clamped))
                                    } else {
                                        fixedDayText = digits
                                    }
                                }
                        }
                    }
                }

                Section {
                    Toggle("BACS early payment", isOn: $bacsEarly)
                        .onChange(of: bacsEarly) { _, new in
                            prefsStore.setBacsEarlyPayment(new)
                        }
                } footer: {
                    Text("Monzo and some banks release BACS payroll a working day before the official payment date.")
                }

                Section("Next Payday") {
                    if let next = nextPayday(schedule: currentSchedule, bacsEarly: bacsEarly) {
                        HStack {
                            Text(nextPaydayLabel(for: next))
                                .font(.body.weight(.medium))
                                .foregroundStyle(Calendar.current.isDateInToday(next) ? .green : .primary)
                            Spacer()
                            Text(next, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Payday Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Payday helpers

func nextPayday(schedule: PaydaySchedule, bacsEarly: Bool = false, after today: Date = Date()) -> Date? {
    let cal = Calendar.current
    let start = cal.startOfDay(for: today)
    for offset in 0...1 {
        guard let monthDate = cal.date(byAdding: .month, value: offset, to: start),
              let candidate = paydayInMonth(of: monthDate, schedule: schedule, bacsEarly: bacsEarly, cal: cal) else { continue }
        if candidate >= start { return candidate }
    }
    return nil
}

func nextPaydayLabel(for date: Date) -> String {
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
    switch days {
    case 0:     return "Payday today!"
    case 1:     return "Payday tomorrow"
    case 2...6: return "Payday in \(days) days"
    default:    return "Next payday"
    }
}

private func paydayInMonth(of date: Date, schedule: PaydaySchedule, bacsEarly: Bool, cal: Calendar) -> Date? {
    let year = cal.component(.year, from: date)
    let month = cal.component(.month, from: date)
    guard let first = cal.date(from: DateComponents(year: year, month: month, day: 1)),
          let range = cal.range(of: .day, in: .month, for: first),
          let lastDay = cal.date(from: DateComponents(year: year, month: month, day: range.count)) else { return nil }

    let base: Date
    switch schedule {
    case .fixedDay(let day):
        guard let d = cal.date(from: DateComponents(year: year, month: month, day: min(day, range.count))) else { return nil }
        base = d
    case .lastWorkingDay:
        base = lastWorkingDay(before: lastDay, cal: cal)
    }

    return bacsEarly ? previousWorkingDay(before: base, cal: cal) : base
}

private func lastWorkingDay(before date: Date, cal: Calendar) -> Date {
    var d = date
    while [1, 7].contains(cal.component(.weekday, from: d)) {
        d = cal.date(byAdding: .day, value: -1, to: d)!
    }
    return d
}

private func previousWorkingDay(before date: Date, cal: Calendar) -> Date {
    var d = cal.date(byAdding: .day, value: -1, to: date)!
    while [1, 7].contains(cal.component(.weekday, from: d)) {
        d = cal.date(byAdding: .day, value: -1, to: d)!
    }
    return d
}
