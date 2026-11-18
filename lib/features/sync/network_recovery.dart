import 'owned_workspace.dart';

/// Three-way comparison; remote-only updates are never treated as local deletions.
class NetworkRecoveryPlan {
  NetworkRecoveryPlan(Map<String,Map<String,dynamic>> before, Map<String,Map<String,dynamic>> local, Map<String,Map<String,dynamic>> remote) {
    merged.addAll(remote);
    for (final key in {...before.keys,...local.keys,...remote.keys}) {
      final item=local[key]??remote[key]??before[key]!;
      if(localCanvasView(item)){if(local[key]!=null)merged[key]=local[key]!;continue;}
      if(sameItem(before[key],local[key])||sameItem(local[key],remote[key]))continue;
      if(!sameItem(before[key],remote[key]))conflicts.add(key);
      if(local[key]==null){merged.remove(key);}else{merged[key]=local[key]!;}
      changes.add({...item,'value':local[key]?['value'],'deleted':local[key]==null||local[key]?['deleted']==true,
        'baseRevision':remote[key]?['revision']??0,
        if(item['kind']=='list:memoBoxes')'previousValue':remote[key]?['value']});
    }
  }
  final merged=<String,Map<String,dynamic>>{};
  final conflicts=<String>{};
  final changes=<Map<String,dynamic>>[];
}
