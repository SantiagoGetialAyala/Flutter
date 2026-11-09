import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'presentation.dart';

class TaskInbox extends StatefulWidget {
  const TaskInbox({
    super.key,
    required this.tasks,
    required this.onOpen,
    required this.onRefresh,
    this.compact = false,
  });
  final List<Map<String, dynamic>> tasks;
  final Future<void> Function(Map<String, dynamic>) onOpen;
  final Future<void> Function() onRefresh;
  final bool compact;
  @override
  State<TaskInbox> createState() => _TaskInboxState();
}

class _TaskInboxState extends State<TaskInbox> {
  String _query = '';
  bool _overdue = false;
  @override
  Widget build(BuildContext context) {
    final tasks = widget.tasks
        .where(
          (t) =>
              (!_overdue || t['overdue'] == true) &&
              '${t['title']}'.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact) ...[
          const Text(
            'Tus pendientes, en un solo lugar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Abre un pendiente para continuar con el trabajo que te corresponde.',
            style: TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar una tarea…',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Vencidas'),
                selected: _overdue,
                onSelected: (v) => setState(() => _overdue = v),
              ),
              TextButton.icon(
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (tasks.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Column(
                children: [
                  Icon(Icons.task_alt, color: AppTheme.forest, size: 30),
                  SizedBox(height: 10),
                  Text(
                    'Sin pendientes en esta vista',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Las tareas aparecerán cuando tengas registros que atender.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        for (final task in widget.compact ? tasks.take(3) : tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: Icon(
                  task['overdue'] == true
                      ? Icons.priority_high_rounded
                      : moduleIcon('${task['module']}'),
                  color: task['overdue'] == true
                      ? const Color(0xFF97472D)
                      : AppTheme.forest,
                ),
                title: Text(
                  '${task['title']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '${friendly(task['status'])}${task['due_at'] != null ? ' · ${task['overdue'] == true ? 'Venció' : 'Fecha'}: ${dateText(task['due_at'])}' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onOpen(task),
              ),
            ),
          ),
      ],
    );
    return widget.compact
        ? content
        : RefreshIndicator(
            onRefresh: widget.onRefresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [content],
            ),
          );
  }
}
