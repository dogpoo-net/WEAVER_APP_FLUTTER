import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const overviewTabsPreference = 'weaver.overviewTabs.v1';
class OverviewTabs {
  OverviewTabs(this.order, this.hidden);
  final List<String> order;
  final Set<String> hidden;
}
Future<OverviewTabs> loadOverviewTabs(List<String> defaults) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(overviewTabsPreference);
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String,dynamic>;
      final order = (json['order'] as List).whereType<String>().where(defaults.contains).toSet().toList();
      order.addAll(defaults.where((name)=>!order.contains(name)));
      final hidden = (json['hidden'] as List).whereType<String>().where(defaults.contains).toSet();
      if (hidden.length == order.length) hidden.remove(order.first);
      return OverviewTabs(order,hidden);
    }
  } catch (_) { /* Invalid or unavailable preferences fall back to all tabs. */ }
  return OverviewTabs(List.of(defaults),{});
}
Future<void> saveOverviewTabs(OverviewTabs tabs) async {
  final prefs=await SharedPreferences.getInstance();
  if(!await prefs.setString(overviewTabsPreference,jsonEncode({'order':tabs.order,'hidden':tabs.hidden.toList()}))) {
    throw StateError('Tab preference write failed');
  }
}
Future<OverviewTabs?> showOverviewTabSettings(BuildContext context, OverviewTabs initial, String Function(String) label) {
  final order=List<String>.of(initial.order), hidden=Set<String>.of(initial.hidden);
  return showDialog<OverviewTabs>(context:context,builder:(context)=>StatefulBuilder(builder:(context,setState)=>AlertDialog(
    title:const Text('탭 설정'),
    content:SizedBox(width:360,height:360,child:ReorderableListView.builder(
      shrinkWrap:true,buildDefaultDragHandles:false,itemCount:order.length,
      onReorderItem:(oldIndex,newIndex)=>setState((){order.insert(newIndex,order.removeAt(oldIndex));}),
      itemBuilder:(context,index){final name=order[index],enabled=!hidden.contains(name);
        return ListTile(key:ValueKey('tab-setting-$name'),dense:true,contentPadding:EdgeInsets.zero,
          leading:ReorderableDragStartListener(index:index,child:const Padding(padding:EdgeInsets.all(8),child:Icon(Icons.drag_handle))),
          title:Text(label(name)),trailing:Switch(value:enabled,onChanged:enabled&&order.length-hidden.length==1?null:(value)=>setState((){if(value){hidden.remove(name);}else{hidden.add(name);}})));
      })),
    actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('취소')),
      FilledButton(onPressed:()=>Navigator.pop(context,OverviewTabs(order,hidden)),child:const Text('적용'))],
  )));
}
