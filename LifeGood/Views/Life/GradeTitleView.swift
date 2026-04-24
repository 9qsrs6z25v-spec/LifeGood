import SwiftUI

struct GradeTitleView: View {
    @EnvironmentObject var lifeStore: LifeStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(lifeStore.departments.enumerated()), id: \.element.id) { index, _ in
                        HStack(spacing: 12) {
                            TextField("部門編號", text: $lifeStore.departments[index].code)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                            TextField("部門名稱", text: $lifeStore.departments[index].name)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                lifeStore.deleteDepartment(lifeStore.departments[index])
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        lifeStore.add(Department())
                    } label: {
                        Label("新增部門", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("部門名稱")
                } footer: {
                    Text("設定公司內部的部門編號與名稱，方便新增部屬時選擇部門。")
                }

                Section {
                    ForEach(Array(lifeStore.gradeTitles.enumerated()), id: \.element.id) { index, _ in
                        HStack(spacing: 12) {
                            TextField("職等", text: $lifeStore.gradeTitles[index].grade)
                                .textFieldStyle(.roundedBorder)
                            TextField("職稱", text: $lifeStore.gradeTitles[index].title)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                lifeStore.deleteGradeTitle(lifeStore.gradeTitles[index])
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        lifeStore.add(GradeTitle())
                    } label: {
                        Label("新增職等", systemImage: "plus.circle")
                            .foregroundStyle(.green)
                    }
                } header: {
                    Text("職等設定")
                } footer: {
                    Text("設定公司內部的職等編號與對應職稱，方便管理部屬與職涯記錄。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("職等對應職稱")
        }
    }
}

#Preview {
    GradeTitleView()
        .environmentObject(LifeStore())
}
