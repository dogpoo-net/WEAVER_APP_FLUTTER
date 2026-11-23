import 'package:collection/collection.dart';
import 'owned_workspace.dart';

/// Three-way comparison; remote-only updates are never treated as local deletions.
class NetworkRecoveryPlan {
  NetworkRecoveryPlan(Map<String,Map<String,dynamic>> before, Map<String,Map<String,dynamic>> local, Map<String,Map<String,dynamic>> remote) {
    merged.addAll(remote);
    for (final key in {...before.keys,...local.keys,...remote.keys}) {
      final item=local[key]??remote[key]??before[key]!;
      if(localCanvasView(item)){if(local[key]!=null)merged[key]=local[key]!;continue;}
      if(sameItem(before[key],local[key])||sameItem(local[key],remote[key]))continue;
      final kind = item['kind'];
      if (kind == 'layout') continue;
      if (kind == 'list:memoBoxes' && before[key] != null && before[key]?['deleted'] != true) {
        // Preserve the placement of newly created content without replaying moves.
        final box = remote[key]?['value'];
        final draft = local[key]?['value'];
        if (box is! Map || draft is! Map) continue;
        final ids = {...box['ids'] as List? ?? []};
        final originalSize = ids.length;
        for (final id in draft['ids'] as List? ?? []) {
          if (['list:elements', 'list:workspacePhotos'].any((type) {
            final member = itemKey(type, id);
            return local.containsKey(member) && sameItem(before[member], null);
          })) ids.add(id);
        }
        if (ids.length == originalSize) continue;
        final updated = {...remote[key]!, 'value': {...box, 'ids': ids.toList()}};
        merged[key] = updated;
        changes.add({...updated, 'deleted': false, 'baseRevision': remote[key]?['revision'] ?? 0, 'previousValue': box});
        continue;
      }
      if(!sameItem(before[key],remote[key])) {
        if (!{'list:elements','list:notes','list:trash'}.contains(kind)) continue;
        final original = before[key]?['value'], draft = local[key]?['value'], server = remote[key]?['value'];
        if (original is Map && draft is Map && server is Map) {
          const equal = DeepCollectionEquality();
          final combined = Map.of(server);
          var needsChoice = false;
          for (final field in {...original.keys, ...draft.keys}) {
            if (equal.equals(original[field],draft[field]) || equal.equals(draft[field],server[field])) continue;
            if (!equal.equals(original[field],server[field])) {
              if (field == 'updatedAt') continue;
              needsChoice = true;
              break;
            }
            if (draft.containsKey(field)) { combined[field] = draft[field]; } else { combined.remove(field); }
          }
          if (!needsChoice) {
            merged[key] = {...item, 'value': combined};
            if (!equal.equals(server,combined)) changes.add({...item,'value':combined,'deleted':false,'baseRevision':remote[key]?['revision']??0});
            continue;
          }
        }
        conflicts.add(key);
      }
      if(local[key]==null){merged.remove(key);}else{merged[key]=local[key]!;}
      changes.add({...item,'value':local[key]?['value'],'deleted':local[key]==null||local[key]?['deleted']==true,
        'baseRevision':remote[key]?['revision']??0,
        if(item['kind']=='list:memoBoxes')'previousValue':remote[key]?['value']});
    }
  }
  List<Map<String,dynamic>> get automatic => changes.where((c) =>
      !conflicts.contains(itemKey(c['kind'], c['id']))).toList();
  final merged=<String,Map<String,dynamic>>{};
  final conflicts=<String>{};
  final changes=<Map<String,dynamic>>[];
}
