import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'capture_models.dart';
import 'location_capture.dart';
import 'regional_tiles.dart';
import 'map_attribution.dart';
import 'map_marker_style.dart';

class LocationEntry {
  const LocationEntry(this.location,this.text);
  final ThoughtLocation location;
  final String text;
}
Future<LocationEntry?> showLocationEditor(BuildContext context,{ThoughtLocation? initial,bool compose=false,bool locateInitially=true,String confirmLabel='저장',String? Function(String)? validate,Future<ThoughtLocation> Function()? locate}) =>
 showDialog<LocationEntry>(context:context,builder:(_)=>LocationEditor(initial:initial,compose:compose,locateInitially:locateInitially,confirmLabel:confirmLabel,validate:validate,locate:locate??captureLocation));
class LocationEditor extends StatefulWidget {
 const LocationEditor({super.key,this.initial,this.compose=false,this.locateInitially=true,this.confirmLabel='저장',this.validate,required this.locate});
 final ThoughtLocation? initial;
 final bool compose,locateInitially;
 final String confirmLabel;
 final String? Function(String)? validate;
 final Future<ThoughtLocation> Function() locate;
 @override State<LocationEditor> createState()=>_LocationEditorState();
}
class _LocationEditorState extends State<LocationEditor> {
 final map=MapController();final text=TextEditingController();Timer? locateTimer;
 ThoughtLocation? selected;bool busy=false;int generation=0;String? error;
 @override void initState(){super.initState();selected=widget.initial;WidgetsBinding.instance.addPostFrameCallback((_){if(mounted && selected==null && widget.locateInitially)locate();});}
 Future<void> locate()async{
  final request=++generation;locateTimer?.cancel();setState((){busy=true;error=null;});
  locateTimer=Timer(const Duration(seconds:25),(){if(mounted&&request==generation)setState((){generation++;busy=false;error='현재 위치를 찾지 못했습니다. 지도에서 원하는 위치를 선택해주세요.';});});
  try{final point=await widget.locate();if(!mounted||request!=generation)return;setState(()=>selected=point);map.move(LatLng(point.latitude,point.longitude),16);}
  catch(_){if(mounted&&request==generation)setState(()=>error='현재 위치를 찾지 못했습니다. 지도에서 원하는 위치를 선택해주세요.');}
  finally{if(mounted&&request==generation){locateTimer?.cancel();setState(()=>busy=false);}}
 }
 void select(LatLng point){setState((){generation++;locateTimer?.cancel();busy=false;error=null;selected=ThoughtLocation(point.latitude,((point.longitude+180)%360)-180,0,DateTime.now(),isCurrentLocation:false);});}
 @override void dispose(){generation++;locateTimer?.cancel();map.dispose();text.dispose();super.dispose();}
 @override Widget build(BuildContext context){
  final point=selected;
  final height=math.max(240.0,math.min(660.0,MediaQuery.sizeOf(context).height-MediaQuery.viewInsetsOf(context).bottom-48));
  return Dialog(insetPadding:const EdgeInsets.all(16),child:SizedBox(width:640,height:height,child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
   Row(children:[Expanded(child:Text(widget.compose?'위치에 생각 남기기':'위치 선택',style:Theme.of(context).textTheme.titleMedium)),IconButton(tooltip:'현재 위치',onPressed:busy?null:locate,icon:const Icon(Icons.my_location))]),
   if(busy)const LinearProgressIndicator(),
   if(error!=null)Text(error!,style:Theme.of(context).textTheme.bodySmall),
   Expanded(child:ClipRect(child:Stack(children:[
    FlutterMap(mapController:map,options:MapOptions(initialCenter:point==null?const LatLng(20,0):LatLng(point.latitude,point.longitude),initialZoom:point==null?2:16,minZoom:2,maxZoom:19,onTap:(_,position)=>select(position)),children:[
     TileLayer(urlTemplate:globalTileTemplate,tileProvider:RegionalTileProvider(),userAgentPackageName:'net.dogpoo.weaver',maxNativeZoom:19),
     MarkerLayer(markers:[if(point!=null)Marker(point:LatLng(point.latitude,point.longitude),width:40,height:40,alignment:Alignment.topCenter,child:Icon(Icons.location_on,size:40,color:locationMarkerColor(point)))]),
    ]),const MapAttribution(),
   ]))),
   if(point!=null)Text('${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',style:Theme.of(context).textTheme.bodySmall),
   if(widget.compose)Padding(padding:const EdgeInsets.only(top:8),child:TextField(key:const ValueKey('geolog-memo-input'),controller:text,minLines:2,maxLines:3,onChanged:(_)=>setState((){}),decoration:const InputDecoration(hintText:'이 위치에 남길 생각',border:OutlineInputBorder()))),
   Row(mainAxisAlignment:MainAxisAlignment.end,children:[
    TextButton(onPressed:()=>Navigator.pop(context),child:const Text('취소')),
    FilledButton(onPressed:point==null||widget.compose&&text.text.trim().isEmpty?null:() {final problem=widget.validate?.call(text.text.trim());if(problem!=null){setState(()=>error=problem);return;}Navigator.pop(context,LocationEntry(point,text.text.trim()));},child:Text(widget.confirmLabel)),
   ]),
  ]))));
 }
}
