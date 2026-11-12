import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../capture/media_storage.dart';

const pendingAccountErasureKey = 'weaver.pending-account-erasure.v1';
Future<void> eraseAccountCache(SharedPreferences preferences, String account,
    {Future<void> Function(String)? clearMedia}) async {
  final scopes = <String>{account, ...(preferences.getStringList('weaver.account.scopes.$account')??<String>[]).where((scope)=>scope==account||scope.startsWith('$account@workspace:'))};
  final keys = preferences.getKeys().toList();
  for (final key in keys.where((k) => k.startsWith('weaver.owned.'))) {
    try {
      final scope = utf8.decode(base64Url.decode(key.substring('weaver.owned.'.length).split('.').first));
      if (scope == account || scope.startsWith('$account@workspace:')) scopes.add(scope);
    } catch (_) { /* Unrelated preference keys are not account data. */ }
  }
  String? claimedScope;
  final claimText = preferences.getString('weaver.guest.claim.v1');
  if (claimText != null) {
    final claim = jsonDecode(claimText) as Map;
    if (claim['account'] == account) {
      claimedScope=claim['scope'] as String;
      scopes.add(claimedScope);
    }
  }
  for (final scope in scopes) {
    await (clearMedia?.call(scope) ?? MediaStorage.clear(owner: scope));
    final prefix = 'weaver.owned.${base64Url.encode(utf8.encode(scope))}.';
    for (final key in preferences.getKeys().where((k) => k.startsWith(prefix)).toList()) {
      if (!await preferences.remove(key)) throw StateError('Local account erasure failed');
    }
  }
  if(claimedScope!=null){
    if(preferences.getString('weaver.guest.owner.v1')==claimedScope)await preferences.remove('weaver.guest.owner.v1');
    await preferences.remove('weaver.guest.claim.v1');
  }
  for (final key in preferences.getKeys().toList()) {
    if (key == 'weaver.account.scopes.$account' || key == 'weaver.selected-workspace.$account' ||
        (key.startsWith('weaver.guest.receipt.') && preferences.get(key) == account)) {
      await preferences.remove(key);
    }
  }
}
Future<void> retryAccountErasures(SharedPreferences preferences) async {
  for (final account in preferences.getStringList(pendingAccountErasureKey) ?? <String>[]) {
    await eraseAccountCache(preferences, account);
    final pending = preferences.getStringList(pendingAccountErasureKey) ?? <String>[];
    pending.remove(account);
    if (pending.isEmpty) { await preferences.remove(pendingAccountErasureKey); }
    else { await preferences.setStringList(pendingAccountErasureKey, pending); }
  }
}
