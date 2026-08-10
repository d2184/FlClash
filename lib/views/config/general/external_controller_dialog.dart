part of '../general.dart';

class _ExternalControllerDialogResult {
  final String value;

  const _ExternalControllerDialogResult({required this.value});
}

class _ExternalControllerDialog extends StatefulWidget {
  final String value;
  final String customValue;

  const _ExternalControllerDialog({
    required this.value,
    required this.customValue,
  });

  @override
  State<_ExternalControllerDialog> createState() =>
      _ExternalControllerDialogState();
}

class _ExternalControllerDialogState extends State<_ExternalControllerDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _controller;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.value.isNotEmpty;
    _controller = TextEditingController(
      text: _enabled
          ? widget.value
          : (widget.customValue.isEmpty
                ? defaultExternalController
                : widget.customValue),
    );
  }

  void _handleSubmit() {
    if (_enabled && _formKey.currentState?.validate() == false) {
      return;
    }
    Navigator.of(context).pop(
      _ExternalControllerDialogResult(
        value: _enabled ? _controller.text.trim() : '',
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonDialog(
      title: appLocalizations.externalController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(appLocalizations.cancel),
        ),
        TextButton(
          onPressed: _handleSubmit,
          child: Text(appLocalizations.submit),
        ),
      ],
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(appLocalizations.enable)),
                Switch(
                  value: _enabled,
                  onChanged: (value) {
                    setState(() {
                      _enabled = value;
                    });
                  },
                ),
              ],
            ),
            AnimatedSize(
              duration: midDuration,
              curve: Curves.easeOutQuad,
              alignment: Alignment.topCenter,
              child: _enabled
                  ? _buildInput(appLocalizations)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(AppLocalizations appLocalizations) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextFormField(
        controller: _controller,
        keyboardType: TextInputType.text,
        maxLines: 1,
        maxLength: TextInputLimits.dnsListen,
        inputFormatters: TextInputLimits.limit(TextInputLimits.dnsListen),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          counterText: '',
          hintText: defaultExternalController,
        ),
        onFieldSubmitted: (_) => _handleSubmit(),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return appLocalizations.emptyTip(
              appLocalizations.externalController,
            );
          }
          return null;
        },
      ),
    );
  }
}
