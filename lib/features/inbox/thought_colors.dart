import 'package:flutter/material.dart';

final thoughtPalette=List<Color>.unmodifiable(List.generate(20,(i)=>HSLColor.fromAHSL(1,i*18,.55,.5).toColor()));
Color thoughtBackgroundForColor(BuildContext context,Color color)=>HSLColor.fromColor(color)
  .withLightness(Theme.of(context).brightness==Brightness.dark ? .25 : .9).toColor();
Color thoughtForegroundForColor(BuildContext context,Color color)=>HSLColor.fromColor(color)
  .withLightness(Theme.of(context).brightness==Brightness.dark ? .9 : .23).toColor();
Future<Color?> pickThoughtColor(BuildContext context,Color? selected)=>showDialog<Color>(
 context:context,builder:(context)=>AlertDialog(title:const Text('생각 색상'),
  content:SizedBox(width:240,height:192,child:GridView.count(key:const ValueKey('thought-palette'),crossAxisCount:5,
   physics:const NeverScrollableScrollPhysics(),children:[for(var i=0;i<thoughtPalette.length;i++)IconButton(
    key:ValueKey('thought-color-$i'),tooltip:'색상 ${i+1}',onPressed:()=>Navigator.pop(context,thoughtPalette[i]),
    icon:Container(width:28,height:28,decoration:BoxDecoration(shape:BoxShape.circle,
      color:thoughtBackgroundForColor(context,thoughtPalette[i]),border:Border.all(color:Theme.of(context).colorScheme.outlineVariant)),
     child:selected==thoughtPalette[i]?Icon(Icons.check,size:18,color:thoughtForegroundForColor(context,thoughtPalette[i])):null),
   )])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('취소'))]));
