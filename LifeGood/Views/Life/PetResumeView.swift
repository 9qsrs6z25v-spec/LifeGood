import SwiftUI

// MARK: - 寵物履歷
//
// [v25.387] 家庭子功能列裡排在「兒女履歷」右邊的那一頁。
//
// 寵物是 FamilyMember 的一個 role（見 FamilyMemberRole.pet），所以這頁的資料來源
// 與兒女履歷完全同一套——相簿、家庭事件、日常紀錄、成長／就醫紀錄、iCloud 同步、
// 完整備份都是現成的，這裡只負責挑出 role == .pet 的成員並用寵物的語言呈現。

struct PetResumeView: View {
    @EnvironmentObject var lifeStore: LifeStore

    @State private var viewingPet: FamilyMember?
    @State private var cardsAppeared = false
    @State private var heroAppeared = false
    @State private var emptyIconPulse = false
    @State private var emptyIconPulseTask: Task<Void, Never>?

    /// 英雄卡主題色：草綠 → 青綠
    private let heroGreen = Color(red: 0.36, green: 0.70, blue: 0.42)
    private let heroTeal = Color(red: 0.20, green: 0.64, blue: 0.60)

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_Hant_TW"); f.dateFormat = "yyyy/M/d"; return f
    }()

    /// 到家日早的排前面；沒到家日的用生日；都沒有就排最後
    private var pets: [FamilyMember] {
        lifeStore.familyMembers
            .filter { $0.role == .pet }
            .sorted { a, b in
                let ka = a.pet?.adoptionDate ?? a.birthday ?? .distantFuture
                let kb = b.pet?.adoptionDate ?? b.birthday ?? .distantFuture
                return ka < kb
            }
    }

    var body: some View {
        // pets 是 filter+sort，一次算好供英雄卡／區塊標題／ForEach／空狀態共用
        //（同型效能修正見 ChildrenResumeView v24.22 ⑱）
        let pets = self.pets
        NavigationStack {
            ScrollView {
                if pets.isEmpty {
                    emptyState.padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        heroStatsCard(pets)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        sectionHeader(pets.count)
                            .padding(.horizontal)
                            .padding(.top, 18)
                        VStack(spacing: 12) {
                            ForEach(Array(pets.enumerated()), id: \.element.id) { idx, pet in
                                petCard(pet)
                                    .onTapGesture { viewingPet = pet }
                                    .opacity(cardsAppeared ? 1 : 0)
                                    .offset(y: cardsAppeared ? 0 : 14)
                                    .animation(
                                        .spring(response: 0.45, dampingFraction: 0.82)
                                            .delay(0.05 * Double(idx)),
                                        value: cardsAppeared
                                    )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("寵物履歷")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { heroAppeared = true }
                cardsAppeared = true
            }
            .sheet(item: $viewingPet) { pet in
                PetDetailView(petId: pet.id)
            }
        }
    }

    // MARK: 英雄統計卡

    private func heroStatsCard(_ pets: [FamilyMember]) -> some View {
        // 物種分桶只掃一次（避免每一格各 filter 一輪）
        var speciesCount: [PetSpecies: Int] = [:]
        var recordCount = 0
        var neutered = 0
        for p in pets {
            let s = p.pet?.species ?? .other
            speciesCount[s, default: 0] += 1
            recordCount += p.childRecords.count
            if p.pet?.isNeutered == true { neutered += 1 }
        }
        let dogs = speciesCount[.dog] ?? 0
        let cats = speciesCount[.cat] ?? 0
        let others = pets.count - dogs - cats

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("毛小孩總覽")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("\(pets.count)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text(neuteredBadge(neutered, total: pets.count))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.30), lineWidth: 0.75))
            }

            Rectangle()
                .fill(Color.white.opacity(0.20))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                heroKpiCell("狗", value: dogs, icon: PetSpecies.dog.icon)
                heroKpiCell("貓", value: cats, icon: PetSpecies.cat.icon)
                if others > 0 {
                    heroKpiCell("其他", value: others, icon: "pawprint.fill")
                }
                heroKpiCell("紀錄", value: recordCount, icon: "list.bullet.rectangle.portrait.fill")
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(colors: [heroGreen, heroTeal],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // 三顆散景圓（140 / 90 / 55pt），對齊全 App 英雄卡規格
                Circle().fill(Color.white.opacity(0.10)).blur(radius: 18)
                    .frame(width: 140, height: 140).offset(x: 110, y: -60)
                Circle().fill(Color.white.opacity(0.08)).blur(radius: 12)
                    .frame(width: 90, height: 90).offset(x: -120, y: 50)
                Circle().fill(Color.white.opacity(0.06)).blur(radius: 8)
                    .frame(width: 55, height: 55).offset(x: 60, y: 62)
                LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                               startPoint: .top, endPoint: .center)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: heroGreen.opacity(0.28), radius: 12, x: 0, y: 6)
        .opacity(heroAppeared ? 1 : 0)
        .offset(y: heroAppeared ? 0 : 16)
    }

    private func heroKpiCell(_ title: String, value: Int, icon: String) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("\(value)")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func neuteredBadge(_ neutered: Int, total: Int) -> String {
        neutered == 0 ? "尚未登記結紮" : "已結紮 \(neutered) / \(total)"
    }

    // MARK: 區塊標題

    private func sectionHeader(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(LinearGradient(colors: [heroGreen, heroGreen.opacity(0.5)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 16)
            Text("我的寵物").font(.subheadline.weight(.semibold))
            Text("\(count) 隻")
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(heroGreen.opacity(0.14)).foregroundStyle(heroGreen)
                .clipShape(Capsule())
            Spacer()
        }
    }

    // MARK: 寵物卡片

    private func petCard(_ pet: FamilyMember) -> some View {
        let accent = PetPalette.color(for: pet.pet?.species ?? .other)
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [accent, accent.opacity(0.40)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.trailing, 13)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [accent.opacity(0.85), accent.opacity(0.45)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Circle()
                        .stroke(accent.opacity(0.18), lineWidth: 0.75)
                        .frame(width: 44, height: 44)
                    Image(systemName: pet.pet?.species.icon ?? "pawprint.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(pet.petDisplayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.85)

                    HStack(spacing: 5) {
                        chip(pet.pet?.summaryLine ?? "未填寫資料", color: accent)
                        if let age = pet.petAgeText {
                            chip(age, color: .orange)
                        }
                    }

                    Text(metaLine(pet))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 4) {
                    if let together = pet.petTogetherText {
                        HStack(spacing: 3) {
                            Image(systemName: "house.fill").font(.system(size: 9))
                            Text("在一起 " + together).font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(accent.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(accent.opacity(0.20), lineWidth: 0.5))
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(.separator).opacity(0.12), lineWidth: 0.75))
        .shadow(color: accent.opacity(0.18), radius: 6, x: 0, y: 3)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        .contentShape(Rectangle())
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.6))
            .lineLimit(1).minimumScaleFactor(0.7)
    }

    /// 卡片第三行：生日／到家日 + 紀錄與相片數（字串在 ViewBuilder 外組好）
    private func metaLine(_ pet: FamilyMember) -> String {
        var parts: [String] = []
        if let bd = pet.birthday {
            parts.append("生日 " + Self.dateFormatter.string(from: bd))
        } else if let ad = pet.pet?.adoptionDate {
            parts.append("到家 " + Self.dateFormatter.string(from: ad))
        }
        if !pet.childRecords.isEmpty { parts.append("紀錄 \(pet.childRecords.count)") }
        if !pet.familyPhotos.isEmpty { parts.append("相片 \(pet.familyPhotos.count)") }
        if parts.isEmpty { parts.append("還沒有任何紀錄") }
        return parts.joined(separator: "・")
    }

    // MARK: 空狀態

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(heroGreen.opacity(0.18), lineWidth: 1)
                    .frame(width: 118, height: 118)
                    .scaleEffect(emptyIconPulse ? 1.10 : 0.94)
                    .opacity(emptyIconPulse ? 0 : 0.9)
                Circle()
                    .stroke(heroGreen.opacity(0.25), lineWidth: 1)
                    .frame(width: 96, height: 96)
                    .scaleEffect(emptyIconPulse ? 1.06 : 0.96)
                    .opacity(emptyIconPulse ? 0.15 : 0.8)
                Circle()
                    .fill(LinearGradient(colors: [heroGreen.opacity(0.20), heroTeal.opacity(0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 78, height: 78)
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(heroGreen)
            }
            Text("還沒有寵物")
                .font(.headline)
            Text("到「家庭」頁按右上的＋新增家庭成員，關係選「寵物」，就會在這裡出現。\n寵物和家人共用同一套相簿、日常紀錄與就醫紀錄。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .onAppear {
            emptyIconPulseTask?.cancel()
            emptyIconPulseTask = Task { @MainActor in
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    emptyIconPulse = true
                }
            }
        }
        .onDisappear {
            emptyIconPulseTask?.cancel()
            emptyIconPulseTask = nil
        }
    }
}

// MARK: - 物種配色

/// 物種 → 主題色。單獨拉出來讓履歷頁與詳情頁共用同一組顏色，
/// 不要兩邊各寫一份 switch 然後慢慢走鐘。
enum PetPalette {
    static func color(for species: PetSpecies) -> Color {
        switch species {
        case .dog:     return Color(red: 0.93, green: 0.58, blue: 0.22)   // 橘
        case .cat:     return Color(red: 0.55, green: 0.45, blue: 0.90)   // 紫
        case .bird:    return Color(red: 0.25, green: 0.66, blue: 0.90)   // 藍
        case .fish:    return Color(red: 0.20, green: 0.70, blue: 0.68)   // 青
        case .rabbit:  return Color(red: 0.92, green: 0.48, blue: 0.62)   // 粉
        case .rodent:  return Color(red: 0.78, green: 0.62, blue: 0.38)   // 土黃
        case .reptile: return Color(red: 0.36, green: 0.70, blue: 0.42)   // 綠
        case .other:   return Color(red: 0.45, green: 0.55, blue: 0.62)   // 灰藍
        }
    }
}
