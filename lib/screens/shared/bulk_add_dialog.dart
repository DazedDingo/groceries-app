import 'package:flutter/material.dart';
import '../../services/text_item_parser.dart';

/// A dialog that accepts multi-line text and returns parsed items.
/// Used by both shopping list and pantry bulk-add flows.
class BulkAddDialog extends StatefulWidget {
  final String title;
  final String hint;

  const BulkAddDialog({
    super.key,
    required this.title,
    this.hint = 'One item per line, e.g.:\n2 kg chicken\n3 packs pasta\nmilk\n6 eggs',
  });

  @override
  State<BulkAddDialog> createState() => _BulkAddDialogState();
}

class _BulkAddDialogState extends State<BulkAddDialog> {
  final _ctrl = TextEditingController();
  List<ParsedTextItem> _preview = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _updatePreview(String text) {
    setState(() => _preview = parseTextLines(text));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            FilledButton(
              onPressed: _preview.isEmpty
                  ? null
                  : () => Navigator.pop(context, _preview),
              child: Text('Add ${_preview.isEmpty ? "" : "(${_preview.length})"}'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ctrl,
                onChanged: _updatePreview,
                maxLines: 8,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              if (_preview.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Preview (${_preview.length} items)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _preview.length,
                    itemBuilder: (_, i) {
                      final item = _preview[i];
                      final detail = item.unit != null
                          ? '${item.quantity} ${item.unit}'
                          : item.quantity > 1
                              ? '×${item.quantity}'
                              : '';
                      return ListTile(
                        dense: true,
                        title: Text(item.name),
                        trailing: detail.isNotEmpty ? Text(detail) : null,
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
