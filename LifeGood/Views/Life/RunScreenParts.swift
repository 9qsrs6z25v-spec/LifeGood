import SwiftUI
import UIKit

// MARK: - 跑步畫面的零件（v25.555，健康 v5；health/judge.md §4.0–4.2、樣稿②-2／②-3、③-B1～B9；build/v5/brief.md §G2）
//
// G2 寫：天空面板（開始前／跑步中／暫停）、GPS 燈膠囊、四顆運動膠囊、直徑 88 的開始圓鈕、大字＋三格（點了換）、
// 「這一公里」小步道、暫停／按住結束、GPS 弱提示條、倒數 3-2-1、位置說明卡、浮在地圖上的膠囊鈕。
// RunTrackingView.swift 只管狀態、地圖、流程；這裡的 view 只畫，按了就呼叫傳進來的閉包，不寫任何 store。
