import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class AgeKeyPage extends ConsumerStatefulWidget {
  const AgeKeyPage({super.key});

  @override
  ConsumerState<AgeKeyPage> createState() => _AgeKeyPageState();
}

class _KeygenState {
  final bool loading;
  final AgeKeygenResult? result;
  final String? error;

  const _KeygenState({this.loading = false, this.result, this.error});
}

class _AgeKeyPageState extends ConsumerState<AgeKeyPage> {
  CoreController get _core => ref.read(coreHandlerProvider);

  final _convertController = TextEditingController();

  _KeygenState _x25519 = const _KeygenState();
  _KeygenState _hybrid = const _KeygenState();

  bool _convertLoading = false;
  AgeConvertResult? _convertResult;
  String? _convertError;

  bool get _anyLoading =>
      _x25519.loading || _hybrid.loading || _convertLoading;

  @override
  void dispose() {
    _convertController.dispose();
    super.dispose();
  }

  Future<void> _runKeygen(
    Future<AgeKeygenResult?> Function() fn,
    void Function(_KeygenState) apply,
  ) async {
    setState(() => apply(const _KeygenState(loading: true)));
    try {
      final result = await fn();
      if (!mounted) return;
      setState(() => apply(_KeygenState(
            result: result,
            error: result == null
                ? context.appLocalizations.ageKeyError
                : result.error?.isNotEmpty == true
                    ? result.error
                    : null,
          )));
    } catch (e) {
      if (!mounted) return;
      setState(() => apply(_KeygenState(error: e.toString())));
    }
  }

  Future<void> _generateX25519() =>
      _runKeygen(_core.ageKeygen, (s) => _x25519 = s);

  Future<void> _generateHybrid() =>
      _runKeygen(_core.ageKeygenPq, (s) => _hybrid = s);

  Future<void> _convert() async {
    final secretKey = _convertController.text.trim();
    if (secretKey.isEmpty) return;
    if (!secretKey.startsWith('AGE-SECRET-KEY-')) {
      setState(() => _convertError =
          context.appLocalizations.ageSecretKeyInvalidFormat);
      return;
    }
    setState(() {
      _convertLoading = true;
      _convertError = null;
      _convertResult = null;
    });
    try {
      final result = await _core.ageConvert(secretKey);
      if (!mounted) return;
      setState(() {
        _convertResult = result;
        _convertError = result == null
            ? context.appLocalizations.ageKeyError
            : result.error?.isNotEmpty == true
                ? result.error
                : null;
        _convertLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _convertError = e.toString();
        _convertLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.appLocalizations;

    return BaseScaffold(
      title: loc.ageKeyManagement,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _InfoCard(),
            const SizedBox(height: 16),
            _KeygenCard(
              title: 'X25519 (age-encryption.org/v1)',
              desc: loc.ageKeyX25519Desc,
              buttonIcon: Icons.key,
              buttonLabel: loc.ageKeyGenX25519,
              onPressed: _anyLoading ? null : _generateX25519,
              state: _x25519,
            ),
            const SizedBox(height: 16),
            _KeygenCard(
              title: 'MLKEM768-X25519',
              desc: loc.ageKeyHybridDesc,
              buttonIcon: Icons.enhanced_encryption,
              buttonLabel: loc.ageKeyGenHybrid,
              onPressed: _anyLoading ? null : _generateHybrid,
              state: _hybrid,
            ),
            const SizedBox(height: 16),
            _ConvertCard(
              controller: _convertController,
              loading: _convertLoading,
              anyLoading: _anyLoading,
              onConvert: _convert,
              result: _convertResult,
              error: _convertError,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    final loc = context.appLocalizations;
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  loc.ageKeyInfoTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(loc.ageKeyInfoDesc),
          ],
        ),
      ),
    );
  }
}

class _KeygenCard extends StatelessWidget {
  final String title;
  final String desc;
  final IconData buttonIcon;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final _KeygenState state;

  const _KeygenCard({
    required this.title,
    required this.desc,
    required this.buttonIcon,
    required this.buttonLabel,
    required this.onPressed,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final loc = context.appLocalizations;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(desc, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onPressed,
              icon: state.loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(buttonIcon),
              label: Text(buttonLabel),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 12),
              _ErrorBox(error: state.error!),
            ],
            if (state.error == null &&
                state.result?.secretKey != null &&
                state.result?.publicKey != null) ...[
              const SizedBox(height: 12),
              _KeyDisplay(label: loc.ageSecretKey, value: state.result!.secretKey!),
              const SizedBox(height: 8),
              _KeyDisplay(label: loc.agePublicKey, value: state.result!.publicKey!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConvertCard extends StatelessWidget {
  final TextEditingController controller;
  final bool loading;
  final bool anyLoading;
  final VoidCallback onConvert;
  final AgeConvertResult? result;
  final String? error;

  const _ConvertCard({
    required this.controller,
    required this.loading,
    required this.anyLoading,
    required this.onConvert,
    required this.result,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    final loc = context.appLocalizations;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(loc.ageKeyConvertTitle,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(loc.ageKeyConvertDesc,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: loc.ageSecretKeyHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: anyLoading ? null : onConvert,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz),
              label: Text(loc.ageKeyConvert),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              _ErrorBox(error: error!),
            ],
            if (error == null && result?.publicKeys != null) ...[
              const SizedBox(height: 12),
              ...result!.publicKeys!.map(
                (key) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _KeyDisplay(label: loc.agePublicKey, value: key),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String error;

  const _ErrorBox({required this.error});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        error,
        style: TextStyle(color: colorScheme.onErrorContainer),
      ),
    );
  }
}

class _KeyDisplay extends StatelessWidget {
  final String label;
  final String value;

  const _KeyDisplay({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
              ),
              const SizedBox(width: 8),
              _CopyButton(value: value),
            ],
          ),
        ),
      ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  final String value;

  const _CopyButton({required this.value});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.appLocalizations.copySuccess),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      icon: const Icon(Icons.copy, size: 18),
      tooltip: context.appLocalizations.copy,
      visualDensity: VisualDensity.compact,
    );
  }
}
