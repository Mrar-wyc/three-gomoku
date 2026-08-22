import 'supabase_service.dart';

/// 一步落子记录（复盘用）。
class MoveRecord {
  final int slot;
  final int idx; // row*19+col

  const MoveRecord(this.slot, this.idx);
}

class MovesService {
  /// 拉取房间全部落子（按 id 正序）。RLS 仅本房成员可读。
  static Future<List<MoveRecord>> fetch(String roomId) async {
    final data = await SupabaseService.client
        .from('moves')
        .select('slot, idx')
        .eq('room_id', roomId)
        .order('id', ascending: true);
    final list = (data as List?) ?? const [];
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return MoveRecord(m['slot'] as int? ?? 0, m['idx'] as int? ?? 0);
    }).toList();
  }
}
