import 'capture_models.dart';
import 'package:flutter/material.dart';

const activeMapMarkerColor=Color(0xFFB52D39);

const currentLocationMarkerColor=Color(0xFF1976D2);
Color locationMarkerColor(ThoughtLocation location)=>location.markerColor!=null?Color(location.markerColor!):location.isCurrentLocation?currentLocationMarkerColor:activeMapMarkerColor;

const markerPalette=<({String name,int value})>[
 (name:'빨강',value:0xFFD50000),(name:'파랑',value:0xFF1565C0),
 (name:'녹색',value:0xFF008000),(name:'노랑',value:0xFFFFD600),
 (name:'검정',value:0xFF111111),(name:'주황',value:0xFFEF6C00),
 (name:'보라',value:0xFF7B1FA2),(name:'자홍',value:0xFFC51162),
 (name:'청록',value:0xFF00838F),(name:'남색',value:0xFF1A237E),
 (name:'진홍',value:0xFF880E4F),(name:'갈색',value:0xFF6D4C41),
 (name:'진초록',value:0xFF1B5E20),(name:'라임',value:0xFF827717),
 (name:'호박색',value:0xFFFFAB00),(name:'다홍',value:0xFFDD2C00),
 (name:'청색',value:0xFF0091EA),(name:'군청',value:0xFF304FFE),
 (name:'진보라',value:0xFF6200EA),(name:'회색',value:0xFF455A64),
];
Future<int?> showMarkerPalette(BuildContext context,Color selected)=>showDialog<int>(
 context:context,builder:(context)=>AlertDialog(title:const Text('마커 색상'),
 content:SizedBox(width:240,height:192,child:GridView.count(crossAxisCount:5,physics:const NeverScrollableScrollPhysics(),children:[
  for(final color in markerPalette)IconButton(key:ValueKey('marker-color-${color.value}'),tooltip:color.name,
   onPressed:()=>Navigator.pop(context,color.value),icon:Container(width:28,height:28,
    decoration:BoxDecoration(color:Color(color.value),shape:BoxShape.circle,border:Border.all(color:Theme.of(context).colorScheme.outlineVariant)),
    child:selected.toARGB32()==color.value?Icon(Icons.check,color:Color(color.value).computeLuminance()>.4?Colors.black:Colors.white,size:18):null)),
 ])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('취소'))]));
