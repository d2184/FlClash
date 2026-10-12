part of '../general.dart';

class _ExternalControllerForm extends ConsumerStatefulWidget {
  const _ExternalControllerForm();

  @override
  ConsumerState<_ExternalControllerForm> createState() =>
      _ExternalControllerFormState();
}

class _ExternalControllerFormState
    extends ConsumerState<_ExternalControllerForm> {
  late final TextEditingController _controller;
  late final TextEditingController _secretController;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final config = ref.read(patchClashConfigProvider);
    final value = config.externalController;
    final customValue = ref.read(appSettingProvider).customExternalController;
    _enabled = value.isNotEmpty;
    _controller = TextEditingController(
      text: _enabled
          ? value
          : (customValue.isEmpty ? defaultExternalController : customValue),
    );
    _secretController = TextEditingController(text: config.secret);
  }

  void _handleToggle(bool value) {
    setState(() {
      _enabled = value;
      if (value && _secretController.text.trim().isEmpty) {
        _secretController.text = generateRandomSecret(32);
      }
    });
  }

  String? _issue(AppLocalizations appLocalizations) {
    if (!_enabled) {
      return null;
    }
    final value = _controller.text.trim();
    if (value.isEmpty) {
      return appLocalizations.emptyTip(appLocalizations.address);
    }
    return validateListenAddress(value, appLocalizations);
  }

  void _handleSave() {
    if (_issue(context.appLocalizations) != null) {
      return;
    }
    final value = _enabled ? _controller.text.trim() : '';
    if (value.isNotEmpty) {
      ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(customExternalController: value));
    }
    final secret = _enabled ? _secretController.text.trim() : '';
    ref
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state
              .copyWith(externalController: value, secret: secret)
              .ensureControllerSecret(),
        );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final issue = _issue(appLocalizations);
    return FormPage(
      title: appLocalizations.externalController,
      onSave: _handleSave,
      error: issue,
      children: [
        generateSection(
          items: [
            FormRow(
              title: appLocalizations.enable,
              onPressed: () => _handleToggle(!_enabled),
              trailing: Switch(value: _enabled, onChanged: _handleToggle),
            ),
            if (_enabled)
              FormRow(
                title: appLocalizations.address,
                invalid: issue != null,
                trailing: FormRowTextField(
                  controller: _controller,
                  hintText: defaultExternalController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: TextInputLimits.limit(
                    TextInputLimits.dnsListen,
                  ),
                  onChanged: (_) => setState(() {}),
                  onFieldSubmitted: (_) => _handleSave(),
                ),
              ),
            if (_enabled)
              FormRow(
                title: appLocalizations.externalControllerSecret,
                trailing: FormRowSecretTextField(
                  controller: _secretController,
                  textInputAction: TextInputAction.done,
                  inputFormatters: TextInputLimits.limit(
                    TextInputLimits.password,
                  ),
                  onFieldSubmitted: (_) => _handleSave(),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
