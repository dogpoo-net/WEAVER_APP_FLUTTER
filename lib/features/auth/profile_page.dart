import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'google_auth.dart';
import 'email_auth.dart';
import 'google_button.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.auth, this.size = 32});
  final GoogleAuthController? auth;
  final double size;
  @override
  Widget build(BuildContext context) {
    final face = ((auth?.profile?['defaultFace'] as int?) ?? 0).clamp(0, 5);
    Widget fallback() => Image.asset(
      'assets/branding/profile/face_$face.png',
      fit: BoxFit.cover,
    );
    final bytes = auth?.profilePhoto;
    final url = auth?.profile?['avatarUrl'] as String?;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: bytes != null
            ? Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => fallback(),
              )
            : url != null && url.isNotEmpty
            ? Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => fallback(),
              )
            : fallback(),
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.auth});
  final GoogleAuthController auth;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool busy = false, linking = false;
  String? failure;
  GoogleAuthController get auth => widget.auth;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await auth.loadProfile();
      if (mounted && auth.client.configured && !(auth.profile?['providers'] as List? ?? const []).contains('google')) { await auth.prepareGoogleLink(); }
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    }
  }

  @override
  void dispose() {
    auth.endGoogleLink();
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> run(Future<void> Function() action, {bool link = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      linking = link;
      failure = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => failure = e is EmailAuthFailure
              ? e.message
              : '변경을 완료하지 못했습니다. 다시 시도해주세요.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          linking = false;
        });
      }
    }
  }

  Future<void> editName() async {
    final field = TextEditingController(text: auth.identity?.displayName ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(
          controller: field,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '이름'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    // The dialog's exit animation can still use its controller.
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
    if (value == null || !mounted) return;
    await run(() async {
      await auth.emailApi.profile('name', {'name': value});
      await auth.loadProfile();
      message('이름을 변경했습니다.');
    });
  }

  Future<void> editPhoto() => run(() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (photo == null || !mounted) return;
    if (await photo.length() > 2097152) {
      throw const EmailAuthFailure('사진은 2MB 이하로 선택해주세요.');
    }
    final bytes = await photo.readAsBytes();
    if (!mounted) return;
    await auth.emailApi.profile('photo', {'image': base64Encode(bytes)});
    await auth.loadProfile();
    message('프로필 사진을 변경했습니다.');
  });
  Future<void> link(String provider) => run(() async {
    final success = provider == 'kakao'
        ? await auth.linkKakao()
        : await auth.linkBrowser(provider);
    if (success) {
      await auth.loadProfile();
      message('계정을 연결했습니다.');
    }
  }, link: true);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: auth,
    builder: (context, _) {
      final providers = (auth.profile?['providers'] as List?) ?? const [];
      final disabled = busy || auth.googleLinkBusy;
      return Scaffold(
        appBar: AppBar(title: const Text('프로필')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Center(
                  child: IconButton(
                    tooltip: '프로필 사진 변경',
                    onPressed: disabled ? null : editPhoto,
                    icon: Stack(
                      children: [
                        ProfileAvatar(auth: auth, size: 112),
                        const Positioned(
                          right: 0,
                          bottom: 0,
                          child: CircleAvatar(
                            radius: 16,
                            child: Icon(Icons.camera_alt_outlined, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        auth.identity?.displayName ?? '',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '이름 변경',
                      iconSize: 18,
                      onPressed: disabled ? null : editName,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                Text(auth.identity?.email ?? '', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                if (failure != null)
                  Text(
                    failure!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (auth.error != null)
                  Text(
                    auth.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (disabled) const LinearProgressIndicator(),
                if (linking)
                  TextButton(
                    onPressed: auth.cancelAccountLink,
                    child: const Text('계정 연결 취소'),
                  ),
                if (auth.profile == null)
                  TextButton(
                    onPressed: disabled ? null : _load,
                    child: const Text('프로필 다시 불러오기'),
                  ),
                if (auth.profile?['emailEnabled'] == true)
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('비밀번호 변경'),
                    subtitle: const Text('이메일 인증 후 변경할 수 있습니다.'),
                    onTap: disabled
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => PasswordChangePage(auth: auth),
                            ),
                          ),
                  ),
                const Divider(),
                const Text('소셜 계정 연결'),
                const SizedBox(height: 12),
                if (providers.contains('google'))
                  const ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Google'),
                    trailing: Text('연결됨'),
                  )
                else if (auth.client.configured)
                  Center(
                    child: googleSignInButton(
                      onPressed: disabled || !auth.ready
                          ? null
                          : auth.startGoogleLink,
                    ),
                  ),
                for (final entry in const {
                  'github': 'GitHub',
                  'gitlab': 'GitLab',
                  'kakao': '카카오',
                  'naver': '네이버',
                }.entries)
                  ListTile(
                    leading: Image.asset(
                      'assets/branding/social/${entry.key}.png',
                      color: entry.key == 'github' && Theme.of(context).brightness == Brightness.dark ? Colors.white : null,
                      width: 24,
                      height: 24,
                    ),
                    title: Text(entry.value),
                    trailing: providers.contains(entry.key)
                        ? const Text('연결됨')
                        : const Icon(Icons.link),
                    enabled:
                        !disabled &&
                        (entry.key != 'kakao' || auth.kakaoClient.configured),
                    onTap:
                        disabled ||
                            providers.contains(entry.key) ||
                            (entry.key == 'kakao' &&
                                !auth.kakaoClient.configured)
                        ? null
                        : () => link(entry.key),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class PasswordChangePage extends StatefulWidget {
  const PasswordChangePage({super.key, required this.auth});
  final GoogleAuthController auth;
  @override
  State<PasswordChangePage> createState() => _PasswordChangePageState();
}

class _PasswordChangePageState extends State<PasswordChangePage> {
  final code = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  bool busy = false, sent = false;
  String? status;
  @override
  void dispose() {
    code.dispose();
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> submit(bool send) async {
    setState(() {
      busy = true;
      status = null;
    });
    try {
      await widget.auth.emailApi.profile(
        send ? 'password/request' : 'password/change',
        send
            ? {}
            : {
                'code': code.text.trim(),
                'password': password.text,
                'passwordConfirmation': confirm.text,
              },
      );
      if (!mounted) return;
      if (send) {
        setState(() {
          sent = true;
          status = '인증코드를 이메일로 보냈습니다. 10분 안에 입력해주세요.';
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('비밀번호를 변경했습니다. 모든 기기에서 로그아웃됩니다. 다시 로그인해주세요.'),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
        await widget.auth.resumeEmailSession();
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => status = e is EmailAuthFailure ? e.message : '요청을 처리하지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('비밀번호 변경')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(widget.auth.identity?.email ?? ''),
            const SizedBox(height: 12),
            const Text('등록된 이메일로 인증코드를 보냅니다. 비밀번호를 변경하면 모든 기기에서 로그아웃됩니다.'),
            TextButton(
              onPressed: busy ? null : () => submit(true),
              child: Text(sent ? '인증코드 다시 받기' : '인증코드 받기'),
            ),
            TextField(
              controller: code,
              enabled: !busy,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(labelText: '이메일 인증코드'),
            ),
            TextField(
              controller: password,
              enabled: !busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '새 비밀번호',
                helperText: '10자 이상, UTF-8 기준 72바이트 이하',
              ),
            ),
            TextField(
              controller: confirm,
              enabled: !busy,
              obscureText: true,
              decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
            ),
            const SizedBox(height: 20),
            if (busy) const LinearProgressIndicator(),
            if (status != null) Text(status!),
            FilledButton(
              onPressed: busy || !sent ? null : () => submit(false),
              child: const Text('비밀번호 변경'),
            ),
          ],
        ),
      ),
    ),
  );
}
