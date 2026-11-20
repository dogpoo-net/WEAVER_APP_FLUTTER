import 'package:flutter/material.dart';

enum ContainerDeletion { containerOnly, withThoughts }

Future<ContainerDeletion?> confirmContainerDeletion(
  BuildContext context, String name, {bool isFolder = false}
) => showDialog<ContainerDeletion>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(isFolder ? '내용을 함께 삭제할까요?' : '내용을 삭제하시겠어요?'),
    content: Text('$name\n\n내용을 유지하고 이 ${isFolder ? '폴더' : '상자'}만 삭제하거나,\n내용을 전부 삭제할 수 있습니다.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
      TextButton(
        onPressed: () => Navigator.pop(context, ContainerDeletion.containerOnly),
        child: const Text('내용 유지'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, ContainerDeletion.withThoughts),
        child: const Text('모두 삭제'),
      ),
    ],
  ),
);

class MemoBoxActions extends StatelessWidget {
  const MemoBoxActions({super.key, required this.onCreate, required this.onCreateThought});

  final VoidCallback onCreate, onCreateThought;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    style: IconButton.styleFrom(
      fixedSize: const Size(36, 40),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    tooltip: '메모상자 관리',
    icon: const Icon(Icons.add),
    onSelected: (action) {
      if (action == 'thought') {
        onCreateThought();
      } else {
        onCreate();
      }
    },
    itemBuilder: (_) => const [
      PopupMenuItem(value: 'thought', child: Text('생각 만들기')),
      PopupMenuItem(value: 'create', child: Text('상자 만들기')),
    ],
  );
}
