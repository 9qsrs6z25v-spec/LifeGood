import SwiftUI
import PhotosUI
import CoreImage.CIFilterBuiltins
import UIKit
import Contacts
import ContactsUI
import VisionKit
import Vision

// MARK: - 聯絡人挑選器（包 CNContactPickerViewController）

struct ContactPickerView: UIViewControllerRepresentable {
    var onPicked: (CNContact) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPickerView
        init(_ parent: ContactPickerView) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onPicked(contact)
            parent.dismiss()
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.dismiss()
        }
    }
}

// MARK: - 名片掃描器（VNDocumentCameraViewController + Vision OCR）

/// 包 VisionKit 的文件掃描 view controller，使用者拍完後丟回掃描到的圖片。
/// 跟系統內建的「文件掃描」UX 一樣：自動偵測邊框、自動拍攝、透視校正。
struct BusinessCardScannerView: UIViewControllerRepresentable {
    var onCapture: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: BusinessCardScannerView
        init(parent: BusinessCardScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            parent.onCapture(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}

// MARK: - 名片 OCR / 欄位解析

/// 用 Vision Framework 對名片影像做 OCR，並以 regex / 關鍵字字典啟發式
/// 把辨識出的文字行對應到 BusinessCard 各欄位（姓名 / 公司 / 職稱 / 電話 / Email / 地址）。
enum BusinessCardOCR {

    struct Parsed {
        var name: String
        var company: String
        var jobTitle: String
        var phones: [String]
        var emails: [String]
        var faxes: [String]
        var address: String
        /// 未指派到任何欄位的剩餘文字，丟到備註讓使用者人工搬位置。
        var note: String
    }

    /// 對單張圖片做 OCR，回傳辨識到的文字行
    static func recognizeText(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }

    /// 根據 OCR 文字行解析欄位
    static func parse(lines: [String]) -> Parsed {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var emails: [String] = []
        var phones: [String] = []
        var faxes: [String] = []
        var address: String?
        var company: String?
        var jobTitle: String?
        var remaining: [String] = []

        // 規則庫
        let emailRegex = try? NSRegularExpression(
            pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        )
        // 台灣手機 09xx-xxx-xxx、市話 0x-xxxx-xxxx，含 (), 空格, 減號變體
        // 後方選擇性接「分機 / ext / # / 轉」+ 1–5 位數，整段被視為同一支號碼
        let phoneRegex = try? NSRegularExpression(
            pattern: "(?:\\+?886[-\\s]?|0)(?:9[-\\s]?\\d[-\\s\\d]{6,12}|[2-8][-\\s\\d()]{6,12})(?:\\s*(?:ext\\.?|EXT\\.?|分機|轉|#)\\s*\\d{1,5})?"
        )
        // 傳真關鍵字：含 fax / FAX / 傳真 即視為傳真行
        let faxKeyword = try? NSRegularExpression(
            pattern: "(?i)fax|傳真", options: []
        )

        let companyKeywords = [
            "公司", "股份有限", "有限公司", "Inc.", "Inc", "Ltd.", "Ltd",
            "Co.", "Co", "Corp", "Corporation", "Group", "集團", "企業",
            "工作室", "Studio", "事務所", "中心", "Center"
        ]
        let titleKeywords = [
            // 商業職稱
            "經理", "總監", "工程師", "助理", "專員", "主任", "執行長",
            "總經理", "副總", "副理", "顧問", "業務", "處長", "副處長",
            "Director", "Manager", "Engineer", "CEO", "CFO", "CTO", "COO",
            "VP", "President", "Founder", "Lead", "Senior", "Principal",
            "Consultant", "Designer", "Developer", "Analyst", "Architect",
            // 教育職稱
            "老師", "教授", "副教授", "助理教授", "講師", "助教", "教練",
            "校長", "副校長", "院長", "副院長", "系主任", "所長",
            "Teacher", "Professor", "Prof.", "Prof", "Lecturer",
            "Coach", "Dean",
            // 醫療職稱
            "醫師", "醫生", "藥師", "護理師", "技師", "心理師",
            "Doctor", "Dr.", "Dr", "Nurse", "Pharmacist",
            // 法律 / 會計 / 設計
            "律師", "會計師", "建築師", "設計師", "記者",
            "Lawyer", "Attorney", "Accountant"
        ]
        let addressKeywords = [
            "市", "縣", "區", "路", "街", "巷", "弄", "號", "樓",
            "鄉", "鎮", "Road", "Rd.", "Street", "St.", "Ave."
        ]

        for line in cleaned {
            // Email（一行可能含多個）
            if let regex = emailRegex {
                let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
                if !matches.isEmpty {
                    var stripped = line
                    for m in matches {
                        if let r = Range(m.range, in: line) {
                            emails.append(String(line[r]))
                            stripped = stripped.replacingOccurrences(of: String(line[r]), with: "")
                        }
                    }
                    stripped = stripped.trimmingCharacters(in: .whitespaces)
                    if !stripped.isEmpty { remaining.append(stripped) }
                    continue
                }
            }
            // 電話 / 傳真（一行可能含多個）
            if let regex = phoneRegex {
                let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
                if !matches.isEmpty {
                    let isFaxLine: Bool = {
                        guard let fr = faxKeyword else { return false }
                        return fr.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
                    }()
                    for m in matches {
                        if let r = Range(m.range, in: line) {
                            let value = String(line[r]).trimmingCharacters(in: .whitespaces)
                            if isFaxLine {
                                faxes.append(value)
                            } else {
                                phones.append(value)
                            }
                        }
                    }
                    continue
                }
            }
            // 地址（含關鍵字 + 較長）
            if address == nil,
               addressKeywords.contains(where: { line.contains($0) }),
               line.count >= 8 {
                address = line
                continue
            }
            // 公司
            if company == nil, companyKeywords.contains(where: { line.contains($0) }) {
                company = line
                continue
            }
            // 職稱
            if jobTitle == nil,
               titleKeywords.contains(where: { line.contains($0) }),
               line.count <= 25 {
                jobTitle = line
                continue
            }
            remaining.append(line)
        }

        // 姓名：先找剩餘行中「2–5 個中文字」的短行
        var name: String?
        for line in remaining {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.count >= 2 && stripped.count <= 5 {
                let hasHan = stripped.unicodeScalars.contains {
                    $0.value >= 0x4E00 && $0.value <= 0x9FFF
                }
                if hasHan {
                    name = stripped
                    break
                }
            }
        }
        // Fallback：找任意短行（2–30 字）
        if name == nil {
            name = remaining.first(where: { $0.count >= 2 && $0.count <= 30 })
        }

        let usedSet: Set<String> = [name ?? "", company ?? "", jobTitle ?? "", address ?? ""]
            .filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }
        let leftoverNote = remaining
            .filter { !usedSet.contains($0) }
            .joined(separator: "\n")

        return Parsed(
            name: name ?? "",
            company: company ?? "",
            jobTitle: jobTitle ?? "",
            phones: phones,
            emails: emails,
            faxes: faxes,
            address: address ?? "",
            note: leftoverNote
        )
    }
}

// MARK: - CNContact → BusinessCard 預設資料

extension BusinessCard {
    /// 把系統聯絡人轉成預填的 BusinessCard，由編輯器再讓使用者確認
    init(fromContact c: CNContact, id: UUID = UUID(), photoFileNameHolder: String? = nil) {
        // 姓名（中文順序：姓 + 名）
        let nameParts = [c.familyName, c.givenName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let fullName = nameParts.isEmpty
            ? "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
            : nameParts.joined()
        // 公司 / 部門 / 職稱
        let company = c.organizationName.trimmingCharacters(in: .whitespaces)
        let department = c.departmentName.trimmingCharacters(in: .whitespaces)
        let jobTitle = c.jobTitle.trimmingCharacters(in: .whitespaces)
        // 是否為傳真 label
        func isFaxLabel(_ label: String?) -> Bool {
            guard let label else { return false }
            return label == CNLabelPhoneNumberWorkFax
                || label == CNLabelPhoneNumberHomeFax
                || label == CNLabelPhoneNumberOtherFax
                || label.lowercased().contains("fax")
                || label.contains("傳真")
        }
        // 電話（非傳真）：依優先順序排列（mobile / iPhone / work / home / main / 其他）
        let phones: [String] = {
            let labelOrder: [String] = [
                CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone,
                CNLabelWork, CNLabelHome, CNLabelPhoneNumberMain
            ]
            let nonFax = c.phoneNumbers.filter { !isFaxLabel($0.label) }
            var ordered: [CNLabeledValue<CNPhoneNumber>] = []
            for label in labelOrder {
                ordered.append(contentsOf: nonFax.filter { $0.label == label })
            }
            ordered.append(contentsOf: nonFax.filter { !labelOrder.contains($0.label ?? "") })
            var seen: Set<String> = []
            return ordered.compactMap { entry in
                let v = entry.value.stringValue.trimmingCharacters(in: .whitespaces)
                guard !v.isEmpty, !seen.contains(v) else { return nil }
                seen.insert(v)
                return v
            }
        }()
        // 傳真：抓 fax label 的號碼
        let faxes: [String] = {
            var seen: Set<String> = []
            return c.phoneNumbers
                .filter { isFaxLabel($0.label) }
                .compactMap { entry in
                    let v = entry.value.stringValue.trimmingCharacters(in: .whitespaces)
                    guard !v.isEmpty, !seen.contains(v) else { return nil }
                    seen.insert(v)
                    return v
                }
        }()
        // Email：work 優先，其他依原序追加
        let emails: [String] = {
            var ordered: [CNLabeledValue<NSString>] = []
            ordered.append(contentsOf: c.emailAddresses.filter { $0.label == CNLabelWork })
            ordered.append(contentsOf: c.emailAddresses.filter { $0.label != CNLabelWork })
            var seen: Set<String> = []
            return ordered.compactMap { entry in
                let v = (entry.value as String).trimmingCharacters(in: .whitespaces)
                guard !v.isEmpty, !seen.contains(v) else { return nil }
                seen.insert(v)
                return v
            }
        }()
        // 地址：優先 work
        let address: String = {
            let labelOrder = [CNLabelWork, CNLabelHome]
            let chosen: CNPostalAddress? = {
                for label in labelOrder {
                    if let match = c.postalAddresses.first(where: { $0.label == label }) {
                        return match.value
                    }
                }
                return c.postalAddresses.first?.value
            }()
            guard let p = chosen else { return "" }
            let parts = [p.country, p.postalCode, p.state,
                         p.city, p.subLocality, p.street]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return parts.joined(separator: " ")
        }()
        // CNContactNoteKey 自 iOS 13 起需特殊 entitlement；沒拿到就跳過
        let note: String = {
            if c.isKeyAvailable(CNContactNoteKey) {
                return c.note.trimmingCharacters(in: .whitespaces)
            }
            return ""
        }()

        self.init(
            id: id,
            name: fullName,
            company: company,
            department: department,
            jobTitle: jobTitle,
            phone: "",
            email: "",
            address: address,
            note: note,
            date: Date(),
            photoFileName: photoFileNameHolder,
            linkedOrgPersonId: nil,
            phones: phones,
            emails: emails,
            faxes: faxes
        )
    }
}

struct BusinessCardView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @State private var showAdd = false
    @State private var viewingCardId: UUID?
    @State private var searchText = ""
    @State private var showPremiumAlert = false
    @State private var showContactPicker = false
    // 拍名片掃描
    @State private var showCardScanner = false
    @State private var scannedDraft: ScannedCardDraft?
    @State private var scanQueue: [ScannedCardDraft] = []
    @State private var isProcessingScan = false
    // 多選 → 加入聯絡人
    @State private var isMultiSelect = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showExportConfirm = false
    @State private var exportAlertMessage: String?

    fileprivate struct ScannedCardDraft: Identifiable {
        let id = UUID()
        let parsed: BusinessCardOCR.Parsed
        let photoData: Data?
    }

    private var filteredCards: [BusinessCard] {
        let sorted = lifeStore.businessCards.sorted { $0.date > $1.date }
        if searchText.isEmpty { return sorted }
        let q = searchText.lowercased()
        return sorted.filter { card in
            card.name.lowercased().contains(q)
            || card.company.lowercased().contains(q)
            || card.jobTitle.lowercased().contains(q)
            || card.department.lowercased().contains(q)
            || card.primaryBusiness.lowercased().contains(q)
            || card.phones.contains(where: { $0.lowercased().contains(q) })
            || card.emails.contains(where: { $0.lowercased().contains(q) })
        }
    }

    private var groupedByCompany: [(key: String, value: [BusinessCard])] {
        let grouped = Dictionary(grouping: filteredCards) { $0.company.isEmpty ? "未分類" : $0.company }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !lifeStore.businessCards.isEmpty {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜尋姓名、公司、職稱、主要業務", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if filteredCards.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("尚無名片").font(.headline).foregroundStyle(.secondary)
                        Text("點擊右上角 + 新增名片").font(.subheadline).foregroundStyle(.tertiary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(groupedByCompany, id: \.key) { company, cards in
                            Section(header: Text(company)) {
                                ForEach(cards) { card in
                                    HStack(spacing: 12) {
                                        if isMultiSelect {
                                            Image(systemName: selectedIds.contains(card.id)
                                                  ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedIds.contains(card.id)
                                                                 ? .green : Color.secondary.opacity(0.5))
                                                .font(.title3)
                                                .transition(.scale.combined(with: .opacity))
                                        }
                                        cardRow(card)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isMultiSelect {
                                            toggleSelection(card.id)
                                        } else if subscription.isPremium {
                                            viewingCardId = card.id
                                        } else {
                                            showPremiumAlert = true
                                        }
                                    }
                                    .onLongPressGesture(minimumDuration: 0.4) {
                                        guard !isMultiSelect, subscription.isPremium else { return }
                                        withAnimation { isMultiSelect = true }
                                        selectedIds = [card.id]
                                    }
                                    .swipeActions(edge: .trailing) {
                                        if !isMultiSelect {
                                            Button(role: .destructive) {
                                                if subscription.isPremium { lifeStore.deleteBusinessCard(card) }
                                                else { showPremiumAlert = true }
                                            } label: { Label("刪除", systemImage: "trash") }

                                            Button {
                                                if subscription.isPremium { duplicateBusinessCard(card) }
                                                else { showPremiumAlert = true }
                                            } label: { Label("複製", systemImage: "doc.on.doc") }
                                            .tint(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("名片")
            .toolbar {
                if isMultiSelect {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") {
                            withAnimation {
                                isMultiSelect = false
                                selectedIds = []
                            }
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("已選 \(selectedIds.count) 張")
                            .font(.headline)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            Button {
                                let all = Set(filteredCards.map { $0.id })
                                selectedIds = (selectedIds == all) ? [] : all
                            } label: {
                                Image(systemName: selectedIds.count == filteredCards.count && !filteredCards.isEmpty
                                      ? "checkmark.circle.fill" : "checklist")
                                    .foregroundStyle(.blue)
                            }
                            Button {
                                if selectedIds.isEmpty { return }
                                showExportConfirm = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(.green)
                            }
                            .disabled(selectedIds.isEmpty)
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        if !lifeStore.businessCards.isEmpty {
                            Button("選取") {
                                withAnimation {
                                    isMultiSelect = true
                                    selectedIds = []
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                if subscription.isPremium { showAdd = true }
                                else { showPremiumAlert = true }
                            } label: {
                                Label("新增空白名片", systemImage: "square.and.pencil")
                            }
                            Button {
                                if subscription.isPremium {
                                    if VNDocumentCameraViewController.isSupported {
                                        showCardScanner = true
                                    }
                                } else { showPremiumAlert = true }
                            } label: {
                                Label("拍名片自動辨識", systemImage: "camera.viewfinder")
                            }
                            Button {
                                if subscription.isPremium { showContactPicker = true }
                                else { showPremiumAlert = true }
                            } label: {
                                Label("從聯絡人匯入", systemImage: "person.crop.circle.badge.plus")
                            }
                        } label: {
                            if isProcessingScan {
                                ProgressView().tint(.green)
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3).foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .confirmationDialog(
                "將 \(selectedIds.count) 張名片加入「聯絡人」？",
                isPresented: $showExportConfirm,
                titleVisibility: .visible
            ) {
                Button("加入聯絡人") {
                    Task { await exportSelectedToContacts() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("會把姓名、公司、職稱、電話、Email、地址、頭像複製到 iOS 聯絡人。LifeGood 中的名片不受影響。")
            }
            .alert("加入聯絡人", isPresented: Binding(
                get: { exportAlertMessage != nil },
                set: { if !$0 { exportAlertMessage = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(exportAlertMessage ?? "")
            }
            .fullScreenCover(isPresented: $showCardScanner) {
                BusinessCardScannerView(
                    onCapture: { images in
                        showCardScanner = false
                        guard !images.isEmpty else { return }
                        isProcessingScan = true
                        Task {
                            var drafts: [ScannedCardDraft] = []
                            for image in images {
                                let lines = await BusinessCardOCR.recognizeText(in: image)
                                let parsed = BusinessCardOCR.parse(lines: lines)
                                let data = image.jpegData(compressionQuality: 0.8)
                                drafts.append(ScannedCardDraft(parsed: parsed, photoData: data))
                            }
                            await MainActor.run {
                                isProcessingScan = false
                                guard let first = drafts.first else { return }
                                scannedDraft = first
                                scanQueue = Array(drafts.dropFirst())
                            }
                        }
                    },
                    onCancel: { showCardScanner = false }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $scannedDraft, onDismiss: {
                // 多張連續編輯：上一張關閉後自動帶出下一張
                guard !scanQueue.isEmpty else { return }
                let next = scanQueue.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    scannedDraft = next
                }
            }) { draft in
                BusinessCardEditor(
                    editing: nil,
                    prefilled: draft.parsed,
                    prefilledPhotoData: draft.photoData
                )
            }
            .sheet(isPresented: $showAdd) {
                BusinessCardEditor(editing: nil)
            }
            .sheet(item: Binding(
                get: { viewingCardId.map { IdentifiableUUID(id: $0) } },
                set: { viewingCardId = $0?.id }
            )) { wrapper in
                BusinessCardDetailView(cardId: wrapper.id)
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerView { contact in
                    importContact(contact)
                }
                .ignoresSafeArea()
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
        }
    }

    /// 列表 row：頭像 + 姓名/職稱 + 公司/部門 + 聯絡方式列 + 日期
    private func cardRow(_ card: BusinessCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView(card)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(card.name.isEmpty ? "未命名" : card.name)
                        .font(.subheadline.weight(.semibold))
                    if !card.jobTitle.isEmpty {
                        Text(card.jobTitle)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if !card.company.isEmpty || !card.department.isEmpty {
                    HStack(spacing: 4) {
                        if !card.company.isEmpty {
                            Text(card.company).font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !card.company.isEmpty && !card.department.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                        }
                        if !card.department.isEmpty {
                            Text(card.department).font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                if !card.phone.isEmpty || !card.email.isEmpty {
                    HStack(spacing: 10) {
                        if !card.phone.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 9))
                                Text(card.phone).font(.caption2)
                            }
                            .foregroundStyle(.green)
                        }
                        if !card.email.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 9))
                                Text(card.email).font(.caption2).lineLimit(1)
                            }
                            .foregroundStyle(.indigo)
                        }
                    }
                }
                if !card.address.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 9))
                        Text(card.address).font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(fmtDate(card.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func avatarView(_ card: BusinessCard) -> some View {
        if let url = card.photoURL,
           let img = UIImage(contentsOfFile: url.path) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            let initial = String((card.name.isEmpty ? card.company : card.name).prefix(1))
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(
                        colors: [.orange, .pink.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                Text(initial)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
        }
    }

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }

    // MARK: - 複製名片

    /// 複製一張名片：新 UUID、頭像照片複寫一份檔案（避免兩張共用同檔被刪掉）；
    /// 不複製 linkedOrgPersonId（避免兩張名片同時對應同一筆組織人員）。
    private func duplicateBusinessCard(_ source: BusinessCard) {
        let newId = UUID()
        var newPhotoFileName: String? = nil
        if let srcName = source.photoFileName {
            let srcURL = BusinessCard.photosDirectory.appendingPathComponent(srcName)
            if let data = try? Data(contentsOf: srcURL) {
                newPhotoFileName = BusinessCard.savePhoto(data, id: newId)
            }
        }
        let copy = BusinessCard(
            id: newId,
            name: source.name,
            company: source.company,
            department: source.department,
            jobTitle: source.jobTitle,
            phone: "",
            email: "",
            address: source.address,
            note: source.note,
            date: Date(),
            photoFileName: newPhotoFileName,
            linkedOrgPersonId: nil,
            phones: source.phones,
            emails: source.emails,
            faxes: source.faxes,
            primaryBusiness: source.primaryBusiness
        )
        lifeStore.add(copy)
    }

    // MARK: - 多選 → 加入聯絡人

    private func toggleSelection(_ id: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedIds.contains(id) { selectedIds.remove(id) }
            else { selectedIds.insert(id) }
        }
    }

    /// 把目前選取的名片寫入 iOS 聯絡人
    @MainActor
    private func exportSelectedToContacts() async {
        let store = CNContactStore()
        // 取得寫入聯絡人權限（read + write 共用 .contacts）
        let granted: Bool
        do {
            granted = try await store.requestAccess(for: .contacts)
        } catch {
            granted = false
        }
        guard granted else {
            exportAlertMessage = "未取得聯絡人權限。請至「設定 → LifeGood → 聯絡人」開啟存取。"
            return
        }
        let cards = lifeStore.businessCards.filter { selectedIds.contains($0.id) }
        guard !cards.isEmpty else { return }

        let request = CNSaveRequest()
        for card in cards {
            let mutable = CNMutableContact()
            mutable.givenName = card.name.trimmingCharacters(in: .whitespaces)
            mutable.organizationName = card.company.trimmingCharacters(in: .whitespaces)
            mutable.departmentName = card.department.trimmingCharacters(in: .whitespaces)
            mutable.jobTitle = card.jobTitle.trimmingCharacters(in: .whitespaces)
            var phoneEntries: [CNLabeledValue<CNPhoneNumber>] = card.phones.enumerated().map { idx, p in
                let label = idx == 0 ? CNLabelPhoneNumberMobile : CNLabelOther
                return CNLabeledValue(label: label, value: CNPhoneNumber(stringValue: p))
            }
            phoneEntries.append(contentsOf: card.faxes.map { fax in
                CNLabeledValue(label: CNLabelPhoneNumberWorkFax, value: CNPhoneNumber(stringValue: fax))
            })
            mutable.phoneNumbers = phoneEntries
            mutable.emailAddresses = card.emails.enumerated().map { idx, e in
                let label = idx == 0 ? CNLabelWork : CNLabelOther
                return CNLabeledValue(label: label, value: e as NSString)
            }
            let trimmedAddr = card.address.trimmingCharacters(in: .whitespaces)
            if !trimmedAddr.isEmpty {
                let addr = CNMutablePostalAddress()
                addr.street = trimmedAddr
                mutable.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: addr)]
            }
            if let name = card.photoFileName {
                let url = BusinessCard.photosDirectory.appendingPathComponent(name)
                if let data = try? Data(contentsOf: url) {
                    mutable.imageData = data
                }
            }
            request.add(mutable, toContainerWithIdentifier: nil)
        }

        do {
            try store.execute(request)
            exportAlertMessage = "已將 \(cards.count) 張名片加入聯絡人。"
            withAnimation {
                isMultiSelect = false
                selectedIds = []
            }
        } catch {
            exportAlertMessage = "寫入失敗：\(error.localizedDescription)"
        }
    }

    // MARK: - 從系統聯絡人匯入

    /// 把 CNContact 轉成 BusinessCard 並加進 lifeStore，匯入完直接打開詳細頁。
    /// 若聯絡人有大頭照，一併存進 BusinessCardPhotos 並設為名片頭像。
    private func importContact(_ c: CNContact) {
        let id = UUID()
        var photoFileName: String? = nil
        if let imgData = c.imageData ?? c.thumbnailImageData {
            photoFileName = BusinessCard.savePhoto(imgData, id: id)
        }
        let card = BusinessCard(fromContact: c, id: id, photoFileNameHolder: photoFileName)
        // 沒有任何欄位就略過
        let isEmpty = card.name.isEmpty && card.company.isEmpty && card.phone.isEmpty
            && card.email.isEmpty && card.address.isEmpty
        guard !isEmpty else { return }
        lifeStore.add(card)
        // 系統 picker 收起後，延遲一點再開詳細頁，避免 sheet 衝突
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            viewingCardId = card.id
        }
    }
}

// MARK: - 名片詳細頁（點 row 開啟）

struct BusinessCardDetailView: View {
    @EnvironmentObject var lifeStore: LifeStore
    @EnvironmentObject var subscription: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let cardId: UUID
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showRescanScanner = false
    @State private var rescanDraft: BusinessCardView.ScannedCardDraft?
    @State private var isRescanning = false
    @State private var showPremiumAlert = false
    @State private var showCamera = false
    @State private var showPhotosPicker = false
    @State private var showAvatarLightbox = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showQRFullscreen = false
    @State private var viewingLinkedOrgPersonId: UUID?

    private var card: BusinessCard {
        lifeStore.businessCards.first(where: { $0.id == cardId })
            ?? BusinessCard(id: cardId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    if card.linkedOrgPersonId != nil {
                        linkedOrgPersonButton
                    }
                    if hasContact {
                        contactCard
                    }
                    metaCard
                    if !card.note.isEmpty {
                        noteCard
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("名片卡片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isRescanning {
                        ProgressView().tint(.green)
                    } else {
                        Menu {
                            Button {
                                if subscription.isPremium { showEdit = true }
                                else { showPremiumAlert = true }
                            } label: {
                                Label("編輯", systemImage: "pencil")
                            }
                            Button {
                                if subscription.isPremium {
                                    if VNDocumentCameraViewController.isSupported {
                                        showRescanScanner = true
                                    }
                                } else { showPremiumAlert = true }
                            } label: {
                                Label("重新拍照辨識", systemImage: "camera.viewfinder")
                            }
                            Divider()
                            Button(role: .destructive) {
                                if subscription.isPremium { showDeleteConfirm = true }
                                else { showPremiumAlert = true }
                            } label: {
                                Label("刪除", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3).foregroundStyle(.green)
                        }
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                BusinessCardEditor(editing: card)
            }
            .fullScreenCover(isPresented: $showRescanScanner) {
                BusinessCardScannerView(
                    onCapture: { images in
                        showRescanScanner = false
                        guard let first = images.first else { return }
                        isRescanning = true
                        Task {
                            let lines = await BusinessCardOCR.recognizeText(in: first)
                            let parsed = BusinessCardOCR.parse(lines: lines)
                            let data = first.jpegData(compressionQuality: 0.8)
                            await MainActor.run {
                                isRescanning = false
                                rescanDraft = BusinessCardView.ScannedCardDraft(parsed: parsed, photoData: data)
                            }
                        }
                    },
                    onCancel: { showRescanScanner = false }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $rescanDraft) { draft in
                // 帶 editing + prefilled → 編輯器以 prefilled 覆寫欄位但保留 id / 連結
                BusinessCardEditor(
                    editing: card,
                    prefilled: draft.parsed,
                    prefilledPhotoData: draft.photoData
                )
            }
            .sheet(item: Binding(
                get: { viewingLinkedOrgPersonId.map { IdentifiableUUID(id: $0) } },
                set: { viewingLinkedOrgPersonId = $0?.id }
            )) { wrapper in
                OrgPersonDetailView(personId: wrapper.id)
            }
            .premiumLockAlert(isPresented: $showPremiumAlert)
            .alert("確定要刪除這張名片嗎？", isPresented: $showDeleteConfirm) {
                Button("刪除", role: .destructive) {
                    // 移除時清掉組織人員端的連結
                    if let pid = card.linkedOrgPersonId,
                       var person = lifeStore.orgPeople.first(where: { $0.id == pid }),
                       person.linkedBusinessCardId == cardId {
                        person.linkedBusinessCardId = nil
                        lifeStore.update(person)
                    }
                    lifeStore.deleteBusinessCard(card)
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var linkedOrgPersonButton: some View {
        Button {
            viewingLinkedOrgPersonId = card.linkedOrgPersonId
        } label: {
            HStack {
                Image(systemName: "building.2.crop.circle").foregroundStyle(.indigo)
                Text("查看公司組織人員").font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero 名片卡

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 16) {
            // 左側文字資訊
            VStack(alignment: .leading, spacing: 6) {
                Text(card.name.isEmpty ? "未命名" : card.name)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if !card.jobTitle.isEmpty {
                    Text(card.jobTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer().frame(height: 4)
                if !card.company.isEmpty {
                    Text(card.company)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                if !card.department.isEmpty {
                    Text(card.department)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                if !card.primaryBusiness.isEmpty {
                    Text("主要業務：\(card.primaryBusiness)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右側：頭像 + QR Code
            VStack(spacing: 10) {
                avatarMenu
                qrCodeView
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 200)
        .background(
            LinearGradient(
                colors: [Color.orange, Color.pink.opacity(0.85), Color.purple.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .padding(.horizontal)
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.85) {
                    saveAvatarData(data)
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                await MainActor.run {
                    saveAvatarData(data)
                    pickerItem = nil
                }
            }
        }
        .sheet(isPresented: $showQRFullscreen) {
            qrFullscreenView
        }
    }

    // MARK: - 頭像（可點選）

    private var avatarMenu: some View {
        Menu {
            if card.photoFileName != nil {
                Button {
                    showAvatarLightbox = true
                } label: {
                    Label("放大檢視", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
            Button {
                showCamera = true
            } label: {
                Label("拍照", systemImage: "camera.fill")
            }
            Button {
                showPhotosPicker = true
            } label: {
                Label("從相簿選取", systemImage: "photo.on.rectangle")
            }
            if card.photoFileName != nil {
                Button(role: .destructive) {
                    removeAvatar()
                } label: {
                    Label("移除照片", systemImage: "trash")
                }
            }
        } label: {
            avatarContent
        }
        .fullScreenCover(isPresented: $showAvatarLightbox) {
            if let url = card.photoURL {
                PhotoLightbox(url: url)
            }
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        ZStack {
            if let url = card.photoURL,
               let img = UIImage(contentsOfFile: url.path) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 76, height: 76)
                    .overlay(
                        Image(systemName: "person.crop.rectangle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.85))
                    )
            }
            // 右下角小相機圖示提示可點選
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .offset(x: 4, y: 4)
                }
            }
            .frame(width: 76, height: 76)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - QR Code

    private var qrCodeView: some View {
        Group {
            if let img = generateQRCode(from: vCardString) {
                Button {
                    showQRFullscreen = true
                } label: {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                        .padding(4)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 76, height: 76)
                    .overlay(Image(systemName: "qrcode").foregroundStyle(.white))
            }
        }
    }

    private var qrFullscreenView: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let img = generateQRCode(from: vCardString, scale: 16) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding()
                }
                Text(card.name.isEmpty ? "名片 QR Code" : "\(card.name) 的名片")
                    .font(.headline)
                Text("掃描後可直接匯入聯絡人")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("名片 QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉") { showQRFullscreen = false }
                }
            }
        }
    }

    // MARK: - 動作

    private func saveAvatarData(_ data: Data) {
        guard var c = lifeStore.businessCards.first(where: { $0.id == cardId }) else { return }
        if let oldName = c.photoFileName { BusinessCard.deletePhoto(oldName) }
        c.photoFileName = BusinessCard.savePhoto(data, id: c.id)
        lifeStore.update(c)
    }

    private func removeAvatar() {
        guard var c = lifeStore.businessCards.first(where: { $0.id == cardId }) else { return }
        if let oldName = c.photoFileName { BusinessCard.deletePhoto(oldName) }
        c.photoFileName = nil
        lifeStore.update(c)
    }

    // MARK: - vCard / QR

    private var vCardString: String {
        var lines: [String] = ["BEGIN:VCARD", "VERSION:3.0"]
        let name = card.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            lines.append("FN:\(name)")
            lines.append("N:\(name);;;;")
        }
        let org = [card.company, card.department]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !org.isEmpty {
            lines.append("ORG:\(org.joined(separator: ";"))")
        }
        if !card.jobTitle.isEmpty {
            lines.append("TITLE:\(card.jobTitle)")
        }
        for (idx, ph) in card.phones.enumerated() {
            // 第一筆用 WORK,VOICE，後續用 OTHER,VOICE 區隔
            let typeTag = idx == 0 ? "WORK,VOICE" : "OTHER,VOICE"
            lines.append("TEL;TYPE=\(typeTag):\(ph)")
        }
        for fx in card.faxes {
            lines.append("TEL;TYPE=WORK,FAX:\(fx)")
        }
        for (idx, em) in card.emails.enumerated() {
            let typeTag = idx == 0 ? "WORK" : "OTHER"
            lines.append("EMAIL;TYPE=\(typeTag):\(em)")
        }
        if !card.address.isEmpty {
            lines.append("ADR;TYPE=WORK:;;\(card.address);;;;")
        }
        if !card.note.isEmpty {
            lines.append("NOTE:\(card.note.replacingOccurrences(of: "\n", with: " "))")
        }
        lines.append("END:VCARD")
        return lines.joined(separator: "\n")
    }

    private func generateQRCode(from string: String, scale: CGFloat = 8) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - 聯絡方式

    private var hasContact: Bool {
        !card.phones.isEmpty || !card.emails.isEmpty || !card.faxes.isEmpty || !card.address.isEmpty
    }

    private var contactCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(card.phones.enumerated()), id: \.offset) { idx, ph in
                contactRow(
                    icon: "phone.fill",
                    label: card.phones.count > 1 ? "電話 \(idx + 1)" : "電話",
                    value: ph,
                    color: .green
                ) { callPhone(ph) }
                if idx < card.phones.count - 1 || !card.faxes.isEmpty || !card.emails.isEmpty || !card.address.isEmpty {
                    Divider().padding(.leading, 48)
                }
            }
            ForEach(Array(card.faxes.enumerated()), id: \.offset) { idx, fx in
                contactRow(
                    icon: "printer.fill",
                    label: card.faxes.count > 1 ? "傳真 \(idx + 1)" : "傳真",
                    value: fx,
                    color: .gray
                ) {
                    // 傳真不支援撥號，改為複製到剪貼簿
                    UIPasteboard.general.string = fx
                }
                if idx < card.faxes.count - 1 || !card.emails.isEmpty || !card.address.isEmpty {
                    Divider().padding(.leading, 48)
                }
            }
            ForEach(Array(card.emails.enumerated()), id: \.offset) { idx, em in
                contactRow(
                    icon: "envelope.fill",
                    label: card.emails.count > 1 ? "Email \(idx + 1)" : "Email",
                    value: em,
                    color: .indigo
                ) { sendEmail(em) }
                if idx < card.emails.count - 1 || !card.address.isEmpty {
                    Divider().padding(.leading, 48)
                }
            }
            if !card.address.isEmpty {
                contactRow(icon: "mappin.and.ellipse", label: "地址", value: card.address, color: .red) {
                    openInMaps(card.address)
                }
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func contactRow(icon: String, label: String, value: String,
                            color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.14)).frame(width: 32, height: 32)
                    Image(systemName: icon).font(.subheadline).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                    Text(value).font(.subheadline).foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 中介資料（收集日期）

    private var metaCard: some View {
        VStack(spacing: 0) {
            metaRow(icon: "calendar", label: "收集日期", value: fmtDate(card.date), color: .gray)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func metaRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.14)).frame(width: 32, height: 32)
                Image(systemName: icon).font(.subheadline).foregroundStyle(color)
            }
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    // MARK: - 備註

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("備註")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(card.note)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - 動作

    private func callPhone(_ phone: String) {
        // 切掉分機後綴（"分機 123" / "ext 123" / "轉 123" / "#123"），避免撥號失敗
        var main = phone
        let cuts = ["分機", "轉", "ext.", "ext", "EXT.", "EXT", "#"]
        for c in cuts {
            if let r = main.range(of: c, options: .caseInsensitive) {
                main = String(main[..<r.lowerBound])
                break
            }
        }
        let cleaned = main.filter { $0.isNumber || $0 == "+" }
        guard !cleaned.isEmpty,
              let url = URL(string: "tel://\(cleaned)") else { return }
        openURL(url)
    }

    private func sendEmail(_ email: String) {
        guard let url = URL(string: "mailto:\(email)") else { return }
        openURL(url)
    }

    private func openInMaps(_ address: String) {
        guard let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else { return }
        openURL(url)
    }

    private func fmtDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/M/d"; return f.string(from: date)
    }
}

// MARK: - UUID Identifiable wrapper（給 .sheet(item:) 用，模組共用）

struct IdentifiableUUID: Identifiable {
    let id: UUID
}

// MARK: - 名片編輯

struct BusinessCardEditor: View {
    @EnvironmentObject var lifeStore: LifeStore
    @Environment(\.dismiss) private var dismiss

    var editing: BusinessCard?
    /// OCR 掃描完帶進來的預填欄位
    var prefilled: BusinessCardOCR.Parsed?
    /// OCR 掃描完帶進來的整張名片照片資料（會存成頭像）
    var prefilledPhotoData: Data?

    @State private var name = ""
    @State private var company = ""
    @State private var department = ""
    @State private var jobTitle = ""
    @State private var primaryBusiness = ""
    @State private var phones: [String] = [""]
    @State private var emails: [String] = [""]
    @State private var faxes: [String] = []
    @State private var address = ""
    @State private var note = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("基本資訊") {
                    TextField("姓名", text: $name)
                    TextField("公司名稱", text: $company)
                    TextField("部門", text: $department)
                    TextField("職稱", text: $jobTitle)
                    TextField("主要業務（可搜尋）", text: $primaryBusiness)
                }
                Section("電話") {
                    ForEach(phones.indices, id: \.self) { idx in
                        HStack {
                            TextField("電話 \(phones.count > 1 ? "\(idx + 1)" : "")",
                                      text: $phones[idx])
                                .keyboardType(.phonePad)
                            if phones.count > 1 {
                                Button(role: .destructive) {
                                    phones.remove(at: idx)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        phones.append("")
                    } label: {
                        Label("新增電話", systemImage: "plus.circle").foregroundStyle(.green)
                    }
                }

                Section("Email") {
                    ForEach(emails.indices, id: \.self) { idx in
                        HStack {
                            TextField("Email \(emails.count > 1 ? "\(idx + 1)" : "")",
                                      text: $emails[idx])
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                            if emails.count > 1 {
                                Button(role: .destructive) {
                                    emails.remove(at: idx)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        emails.append("")
                    } label: {
                        Label("新增 Email", systemImage: "plus.circle").foregroundStyle(.green)
                    }
                }

                Section("傳真") {
                    ForEach(faxes.indices, id: \.self) { idx in
                        HStack {
                            TextField("傳真 \(faxes.count > 1 ? "\(idx + 1)" : "")",
                                      text: $faxes[idx])
                                .keyboardType(.phonePad)
                            Button(role: .destructive) {
                                faxes.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        faxes.append("")
                    } label: {
                        Label("新增傳真", systemImage: "plus.circle").foregroundStyle(.green)
                    }
                }

                Section("地址") {
                    TextField("地址", text: $address)
                }
                Section("其他") {
                    DatePicker("收集日期", selection: $date, displayedComponents: .date)
                    TextField("備註", text: $note, axis: .vertical).lineLimit(2...5)
                }
                if editing != nil {
                    Section {
                        Button(role: .destructive) {
                            if let e = editing { lifeStore.deleteBusinessCard(e) }
                            dismiss()
                        } label: { Label("刪除名片", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(editing != nil ? "編輯名片" : "新增名片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing != nil ? "儲存" : "新增") { save() }
                        .bold().foregroundStyle(.green)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // 預填值（拍名片掃描 / 重新拍照辨識）優先；編輯模式下用 prefilled
                // 覆蓋既有欄位，但保留 date 與部門（OCR 抓不到部門）
                if let p = prefilled {
                    name = p.name; company = p.company; jobTitle = p.jobTitle
                    phones = p.phones.isEmpty ? [""] : p.phones
                    emails = p.emails.isEmpty ? [""] : p.emails
                    faxes = p.faxes
                    address = p.address
                    note = p.note
                    date = editing?.date ?? Date()
                    department = editing?.department ?? ""
                } else if let e = editing {
                    name = e.name; company = e.company; department = e.department
                    jobTitle = e.jobTitle
                    primaryBusiness = e.primaryBusiness
                    phones = e.phones.isEmpty ? [""] : e.phones
                    emails = e.emails.isEmpty ? [""] : e.emails
                    faxes = e.faxes
                    address = e.address; note = e.note; date = e.date
                }
            }
        }
    }

    private func save() {
        let id = editing?.id ?? UUID()
        // 新增 / 重新拍照辨識：有新的掃描照片時就用它，並把舊照片刪掉
        var photoFileName = editing?.photoFileName
        if let data = prefilledPhotoData {
            if let oldName = photoFileName {
                BusinessCard.deletePhoto(oldName)
            }
            photoFileName = BusinessCard.savePhoto(data, id: id)
        }
        let cleanedPhones = phones
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cleanedEmails = emails
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cleanedFaxes = faxes
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let card = BusinessCard(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            company: company.trimmingCharacters(in: .whitespaces),
            department: department.trimmingCharacters(in: .whitespaces),
            jobTitle: jobTitle.trimmingCharacters(in: .whitespaces),
            phone: "",
            email: "",
            address: address.trimmingCharacters(in: .whitespaces),
            note: note.trimmingCharacters(in: .whitespaces),
            date: date,
            photoFileName: photoFileName,
            linkedOrgPersonId: editing?.linkedOrgPersonId,
            phones: cleanedPhones,
            emails: cleanedEmails,
            faxes: cleanedFaxes,
            primaryBusiness: primaryBusiness.trimmingCharacters(in: .whitespaces)
        )
        if editing != nil { lifeStore.update(card) } else { lifeStore.add(card) }
        dismiss()
    }
}
