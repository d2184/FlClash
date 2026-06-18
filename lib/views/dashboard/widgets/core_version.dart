import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class CoreVersion extends ConsumerStatefulWidget {
  const CoreVersion({super.key});

  @override
  ConsumerState<CoreVersion> createState() => _CoreVersionState();
}

class _CoreVersionState extends ConsumerState<CoreVersion> {
  CoreController get _core => ref.read(coreHandlerProvider);

  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final version = await _core.getCoreVersion();
    if (!mounted) return;
    setState(() => _version = version);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        radius: AppCorner.lg,
        info: Info(
          label: appLocalizations.coreVersion,
          iconData: Icons.memory,
        ),
        onPressed: () {},
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(top: 0),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: globalState.measure.bodyMediumHeight + 2,
                child: FadeThroughBox(
                  child: _version != null
                      ? TooltipText(
                          text: Text(
                            _version!,
                            style: context.textTheme.bodyMedium?.toLight
                                .adjustSize(1),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.all(2),
                          child: const AspectRatio(
                            aspectRatio: 1,
                            child: CommonCircleLoading(),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
