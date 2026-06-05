//
//  Syncable.swift
//  MyFavor
//
//  云同步元数据 — 所有需要同步的模型都包含这些字段
//

import Foundation

/// 同步状态机
enum SyncStatus: String, Codable {
    case localOnly   = "local"      // 仅本地,尚未上传
    case synced      = "synced"     // 已与服务器一致
    case dirty       = "dirty"      // 本地有改动,待推
    case conflicted  = "conflict"   // 服务端与本地有冲突
}
