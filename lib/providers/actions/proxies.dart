part of '../action.dart';

class _DelayTestTarget {
  const _DelayTestTarget({
    required this.proxyName,
    required this.testUrl,
    required this.key,
    this.providerName,
  });

  final String proxyName;
  final String testUrl;
  final String key;
  final String? providerName;
}

class _DelayTestJob {
  _DelayTestJob(Iterable<String> keys) : held = keys.toSet();

  final Set<String> held;
  bool cancelled = false;
}

typedef _ProxySelectionKey = ({int profileId, String groupName});

final class _ProxySelectionRequest {
  const _ProxySelectionRequest({
    required this.profileId,
    required this.groupName,
    required this.proxyName,
  });

  final int profileId;
  final String groupName;
  final String proxyName;

  _ProxySelectionKey get key => (profileId: profileId, groupName: groupName);
}

final class ProxyChangeException implements Exception {
  final String message;

  const ProxyChangeException(this.message);

  @override
  String toString() => message;
}

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  final TaskPool _delayTestPool = TaskPool(maxConcurrentDelayTests);

  final List<_DelayTestJob> _delayTestJobs = [];

  final Map<_ProxySelectionKey, _ProxySelectionRequest> _latestRequests = {};

  final Map<_ProxySelectionKey, SerialTaskScheduler> _schedulers = {};

  final Set<_ProxySelectionKey> _pendingChanges = {};

  static const _changeProxyTimeout = Duration(seconds: 30);

  @override
  void build() {
    ref.listen(coreStatusProvider, (_, next) {
      if (next != CoreStatus.connected) {
        cancelDelayTests();
      }
    });
  }

  void cancelDelayTests() {
    for (final job in _delayTestJobs) {
      job.cancelled = true;
      job.held.clear();
    }
    ref.read(pendingDelayTestsProvider.notifier).clear();
  }

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    final request = _ProxySelectionRequest(
      profileId: currentProfile.id,
      groupName: groupName,
      proxyName: proxyName,
    );
    _latestRequests[request.key] = request;
    final tag =
        '${FunctionTag.changeProxy.name}:${request.profileId}:$groupName';
    debouncer.call(tag, () {
      _schedulers
          .putIfAbsent(request.key, SerialTaskScheduler.new)
          .runDetached(tag, () => _applyChange(request));
    });
  }

  Future<void> updateGroups() async {
    if (!ref.mounted) return;
    try {
      commonPrint.log('updateGroups');
      final sortType = ref.read(
        proxiesStyleSettingProvider.select((state) => state.sortType),
      );
      final delayMap = ref.read(delayDataSourceProvider);
      final testUrl = ref.read(
        appSettingProvider.select((state) => state.testUrl),
      );
      final selectedMap = ref.read(
        currentProfileProvider.select((state) => state?.selectedMap ?? {}),
      );
      final groups = await retry<List<Group>>(
        task: () async {
          try {
            return await _core.getProxiesGroups(
              selectedMap: selectedMap,
              sortType: sortType,
              delayMap: delayMap,
              defaultTestUrl: testUrl,
            );
          } catch (e) {
            commonPrint.log(
              'updateGroups error: $e',
              logLevel: coreFailureLogLevel(e),
            );
            return [];
          }
        },
        retryIf: (res) => res.isEmpty,
      );
      if (!ref.mounted) return;
      ref.read(groupsProvider.notifier).value = groups;
    } catch (e) {
      // The Core failure path already runs inside the retry task above; a
      // throw here only means ref.read hit a disposed container or the
      // groupsProvider write itself failed.
      commonPrint.log(
        'updateGroups failed: $e',
        logLevel: coreFailureLogLevel(e),
      );
    }
  }

  void updateCurrentGroupName(String groupName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(currentGroupName: groupName));
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    ref
        .read(profilesProvider.notifier)
        .put(currentProfile.copyWith(unfoldSet: value));
  }

  void setDelay(Delay delay) {
    ref.read(delayDataSourceProvider.notifier).setDelay(delay);
  }

  bool hasPendingChange(int? profileId, String groupName) {
    if (profileId == null) return false;
    return _pendingChanges.contains((profileId: profileId, groupName: groupName));
  }

  bool _isCurrent(_ProxySelectionRequest request) =>
      identical(_latestRequests[request.key], request);

  void _completeRequest(_ProxySelectionRequest request) {
    if (_isCurrent(request)) _latestRequests.remove(request.key);
  }

  void _finishRequest(_ProxySelectionRequest request) {
    _completeRequest(request);
    updateGroupsDebounce();
  }

  Future<void> _applyChange(_ProxySelectionRequest request) async {
    if (!_isCurrent(request)) return;
    if (ref.read(currentProfileProvider)?.id != request.profileId) {
      _completeRequest(request);
      return;
    }

    _pendingChanges.add(request.key);
    try {
      await _requestCoreChange(request);
    } on ProxyChangeException catch (e) {
      if (!ref.mounted) return;
      _pendingChanges.remove(request.key);
      _handleRejectedChange(request, e);
      return;
    } catch (e) {
      if (!ref.mounted) return;
      _pendingChanges.remove(request.key);
      _handleFailedChange(request, e);
      return;
    }

    if (!ref.mounted) return;
    if (ref.read(currentProfileProvider)?.id == request.profileId) {
      ref.read(profilesActionProvider.notifier).setProxySelection(
        profileId: request.profileId,
        groupName: request.groupName,
        proxyName: request.proxyName.isEmpty ? null : request.proxyName,
      );
    }
    _pendingChanges.remove(request.key);
    _finishRequest(request);
    unawaited(_cleanupConnections());
  }

  Future<void> _requestCoreChange(_ProxySelectionRequest request) async {
    final message = await _core
        .changeProxy(
          ChangeProxyParams(
            groupName: request.groupName,
            proxyName: request.proxyName,
          ),
        )
        .timeout(_changeProxyTimeout);
    if (message.isNotEmpty) throw ProxyChangeException(message);
  }

  void _handleRejectedChange(
    _ProxySelectionRequest request,
    ProxyChangeException error,
  ) {
    commonPrint.log(
      'changeProxy rejected: '
      '${request.groupName} -> ${request.proxyName}: ${error.message}',
      logLevel: LogLevel.warning,
    );
    if (_isCurrent(request)) {
      dialogs.showNotifier(error.message, level: MessageLevel.error);
    }
    _finishRequest(request);
  }

  void _handleFailedChange(_ProxySelectionRequest request, Object error) {
    commonPrint.log(
      'changeProxy failed: '
      '${request.groupName} -> ${request.proxyName}: $error',
      logLevel: coreFailureLogLevel(error),
    );
    if (_isCurrent(request)) {
      dialogs.showNotifier(
        error is TimeoutException
            ? currentAppLocalizations.proxyChangeTimeout
            : error.toString(),
        level: MessageLevel.error,
      );
    }
    _finishRequest(request);
  }

  Future<void> _cleanupConnections() async {
    try {
      if (ref.read(appSettingProvider).closeConnections) {
        await _core.closeConnections();
      } else {
        await _core.resetConnections();
      }
    } catch (e) {
      commonPrint.log(
        'changeProxy connections cleanup error: $e',
        logLevel: coreFailureLogLevel(e),
      );
    }
    if (!ref.mounted) return;
    ref.read(checkIpNumProvider.notifier).add();
  }

  Future<String> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      final message = await _core.updateExternalProvider(
        providerName: provider.name,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
      return '';
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<String> sideLoadExternalProvider(
    ExternalProvider provider,
    String data, {
    bool showLoading = false,
  }) async {
    final operation = showLoading
        ? ref
              .read(updatingKeysProvider.notifier)
              .start(provider.updatingKey, scope: UpdatingScope.core)
        : null;
    try {
      final message = await _core.sideLoadExternalProvider(
        providerName: provider.name,
        data: data,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
      return '';
    } finally {
      if (operation != null) {
        ref
            .read(updatingKeysProvider.notifier)
            .stop(provider.updatingKey, operation);
      }
    }
  }

  Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) {
    return _runDelayTests([proxy], testUrl);
  }

  Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
    await _runDelayTests(proxies, testUrl);
    ref.read(sortNumProvider.notifier).add();
  }

  List<_DelayTestTarget> _resolveDelayTestTargets(
    List<Proxy> proxies,
    String? testUrl,
  ) {
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    final fallbackTestUrl = ref.read(realTestUrlProvider(testUrl));
    final seen = <String>{};
    final targets = <_DelayTestTarget>[];
    for (final proxy in proxies) {
      final state = computeRealSelectedProxyState(
        proxy.name,
        groups: groups,
        selectedMap: selectedMap,
        providerName: proxy.providerName,
      );
      if (state.proxyName.isEmpty) {
        continue;
      }
      final currentTestUrl = state.testUrl.takeFirstValid([fallbackTestUrl]);
      final key = delayTestKey(currentTestUrl, state.proxyName);
      if (!seen.add(key)) {
        continue;
      }
      targets.add(
        _DelayTestTarget(
          proxyName: state.proxyName,
          testUrl: currentTestUrl,
          key: key,
          providerName: state.providerName,
        ),
      );
    }
    return targets;
  }

  Future<void> _runDelayTests(List<Proxy> proxies, String? testUrl) async {
    final targets = _resolveDelayTestTargets(proxies, testUrl);
    if (targets.isEmpty) {
      return;
    }
    final pending = ref.read(pendingDelayTestsProvider.notifier);
    final job = _DelayTestJob(targets.map((target) => target.key));
    _delayTestJobs.add(job);
    pending.acquire(job.held);
    try {
      await Future.wait(
        targets.map(
          (target) => _delayTestPool.run(() => _runDelayTest(job, target)),
        ),
      );
    } finally {
      _delayTestJobs.remove(job);
      final abandoned = job.held.toList();
      job.held.clear();
      pending.release(abandoned);
    }
  }

  Future<void> _runDelayTest(_DelayTestJob job, _DelayTestTarget target) async {
    if (job.cancelled) {
      return;
    }
    try {
      final delay = await _core.getDelay(
        target.testUrl,
        target.proxyName,
        target.providerName,
      );
      if (delay != null && !job.cancelled) {
        setDelay(delay);
      }
    } catch (error) {
      if (error is CoreMethodException && error.isCoreUnavailable) {
        job.cancelled = true;
      }
      commonPrint.log(
        'Delay test failed for ${target.proxyName}: $error',
        logLevel: coreFailureLogLevel(error),
      );
    } finally {
      if (job.held.remove(target.key)) {
        ref.read(pendingDelayTestsProvider.notifier).release([target.key]);
      }
    }
  }
}
