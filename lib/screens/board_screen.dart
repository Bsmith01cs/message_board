import 'package:flutter/material.dart';

import '../models/board_message.dart';
import '../services/auth_service.dart';
import '../services/board_service.dart';
import '../services/user_record_service.dart';

/// Formats a message time for display, or reports a pending server write.
String formatMessageTime(DateTime? time) {
  if (time == null) return 'Sending…';
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$month/$day/${local.year} $hour:$minute';
}

/// The message board. Reached only through ProfileGate, so [author] is always
/// a complete profile. All Firestore work goes through BoardService.
class BoardScreen extends StatefulWidget {
  const BoardScreen({
    super.key,
    required this.author,
    required this.authService,
    required this.boardService,
  });

  final UserRecord author;
  final AuthService authService;
  final BoardService boardService;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final _composerController = TextEditingController();

  /// Subscribed once, so ordinary rebuilds do not restart the stream.
  late final Stream<List<BoardMessage>> _messages = widget.boardService
      .messageBoard();

  bool _isPosting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _composerController.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_isPosting) return;

    final text = _composerController.text;
    if (!isValidMessageText(text)) {
      setState(() => _errorMessage = 'Enter a message before posting.');
      return;
    }

    setState(() {
      _isPosting = true;
      _errorMessage = null;
    });

    try {
      await widget.boardService.postMessage(
        text: text,
        authorName: authorNameFrom(widget.author),
      );
      // Cleared only once Firestore has accepted the write. The stream brings
      // the new message back; nothing is added to a local list.
      _composerController.clear();
    } catch (error) {
      // The typed text is left in the composer so nothing is lost.
      if (mounted) setState(() => _errorMessage = friendlyBoardError(error));
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _editMessage(BoardMessage message) {
    return showDialog<void>(
      context: context,
      builder: (_) => EditMessageDialog(
        message: message,
        boardService: widget.boardService,
      ),
    );
  }

  Future<void> _deleteMessage(BoardMessage message) {
    return showDialog<void>(
      context: context,
      builder: (_) => DeleteMessageDialog(
        message: message,
        boardService: widget.boardService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = authorNameFrom(widget.author);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Board'),
        actions: [
          IconButton(
            onPressed: widget.authService.signOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Signed in as $displayName',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildMessageList()),
            const Divider(height: 1),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<List<BoardMessage>>(
      stream: _messages,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _CenteredNotice(
            icon: Icons.cloud_off,
            title: 'Could not load the board',
            message: friendlyBoardError(snapshot.error!),
            isError: true,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final messages = snapshot.data ?? const <BoardMessage>[];
        if (messages.isEmpty) {
          return const _CenteredNotice(
            icon: Icons.forum_outlined,
            title: 'No messages yet',
            message: 'Post the first message to start the board.',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            // The profile document ID is the Firebase Auth UID.
            final isOwned = message.isOwnedBy(widget.author.uid);
            return _MessageCard(
              message: message,
              isOwned: isOwned,
              onEdit: isOwned ? () => _editMessage(message) : null,
              onDelete: isOwned ? () => _deleteMessage(message) : null,
            );
          },
        );
      },
    );
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _composerController,
                  enabled: !_isPosting,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _isPosting ? null : _post,
                child: _isPosting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Post'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.isOwned,
    this.onEdit,
    this.onDelete,
  });

  final BoardMessage message;

  /// Whether the signed-in user wrote this message. Controls what the UI
  /// offers only; Firestore Security Rules enforce ownership for real.
  final bool isOwned;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    message.authorName.isEmpty
                        ? 'Unknown author'
                        : message.authorName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  formatMessageTime(message.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(message.text, style: theme.textTheme.bodyMedium),
            if (message.isEdited)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Edited',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (isOwned)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Edits one existing message. Closes only after Firestore accepts the write.
class EditMessageDialog extends StatefulWidget {
  const EditMessageDialog({
    super.key,
    required this.message,
    required this.boardService,
  });

  final BoardMessage message;
  final BoardService boardService;

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late final _controller = TextEditingController(text: widget.message.text);

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final text = _controller.text;
    if (!isValidMessageText(text)) {
      setState(() => _errorMessage = 'A message cannot be empty.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await widget.boardService.editMessage(
        messageId: widget.message.id,
        text: text,
      );
      // The stream brings the updated text back; nothing is changed locally.
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      // The dialog stays open with the typed text intact.
      if (mounted) setState(() => _errorMessage = friendlyBoardError(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Edit Message'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            enabled: !_isSaving,
            minLines: 1,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Confirms deletion of one message before anything is removed.
class DeleteMessageDialog extends StatefulWidget {
  const DeleteMessageDialog({
    super.key,
    required this.message,
    required this.boardService,
  });

  final BoardMessage message;
  final BoardService boardService;

  @override
  State<DeleteMessageDialog> createState() => _DeleteMessageDialogState();
}

class _DeleteMessageDialogState extends State<DeleteMessageDialog> {
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _delete() async {
    if (_isDeleting) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await widget.boardService.deleteMessage(widget.message.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = friendlyBoardError(error));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Delete Message?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('This message will be removed from the board.'),
          const SizedBox(height: 12),
          Text(
            widget.message.text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isDeleting ? null : _delete,
          child: _isDeleting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete'),
        ),
      ],
    );
  }
}

class _CenteredNotice extends StatelessWidget {
  const _CenteredNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 56,
              color: isError
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
