import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:weaver/features/auth/email_auth.dart';
import 'memory_session_store.dart';
EmailAuthApi testServerAuth({MemorySessionStore? store})=>EmailAuthApi(store:store??MemorySessionStore(),client:MockClient((request)async{
  if(request.url.path.contains('/workspace/'))return http.Response('{"revision":0,"changes":[]}',200);
  if(request.url.path.endsWith('/logout'))return http.Response('{}',200);
  return http.Response(jsonEncode({'id':'server-user','email':'user@example.com','name':'Test','refreshToken':'refresh','accessToken':'access','expiresIn':1800}),200);
}));
