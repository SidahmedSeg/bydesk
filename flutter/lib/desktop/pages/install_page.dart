import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

// Brand palette for the installer. Kept local so the installer stays visually
// fixed regardless of the user's light/dark theme.
const _kBrand = Color(0xFF1246E6);
const _kBrandDeep = Color(0xFF0A2472);
const _kTagline = 'Secure remote desktop';

class InstallPage extends StatefulWidget {
  const InstallPage({Key? key}) : super(key: key);

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  @override
  Widget build(BuildContext context) {
    return DragToResizeArea(
      resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
      enableResizeEdges: windowManagerEnableResizeEdges,
      child: const Scaffold(
        backgroundColor: Colors.transparent,
        body: _InstallPageBody(),
      ),
    );
  }
}

class _InstallPageBody extends StatefulWidget {
  const _InstallPageBody({Key? key}) : super(key: key);

  @override
  State<_InstallPageBody> createState() => _InstallPageBodyState();
}

class _InstallPageBodyState extends State<_InstallPageBody>
    with WindowListener {
  late final TextEditingController controller;
  final RxBool startmenu = true.obs;
  final RxBool desktopicon = true.obs;
  final RxBool printer = false.obs;
  final RxBool showProgress = false.obs;
  final RxBool btnEnabled = true.obs;
  final RxBool showAdvanced = false.obs;

  // Stage labels shown while the elevated install script runs. The installer
  // backend reports no progress, so these advance on a timer and hold on the
  // final one until the process exits.
  static const _stages = [
    'Preparing files',
    'Copying ByDesk',
    'Registering service',
    'Creating shortcuts',
    'Finishing up',
  ];
  final RxInt stageIndex = 0.obs;
  Timer? _stageTimer;

  _InstallPageBodyState() {
    controller = TextEditingController(text: bind.installInstallPath());
    final installOptions = jsonDecode(bind.installInstallOptions());
    startmenu.value = installOptions['STARTMENUSHORTCUTS'] != '0';
    desktopicon.value = installOptions['DESKTOPSHORTCUTS'] != '0';
    printer.value = installOptions['PRINTER'] == '1';
  }

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    gFFI.close();
    super.onWindowClose();
    windowManager.setPreventClose(false);
    windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Brand gradient backdrop.
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kBrand, _kBrandDeep],
              ),
            ),
          ),
        ),
        // Soft light blooms, blurred by the glass card in front of them.
        Positioned(top: -120, left: -90, child: _blob(320, Colors.white, .28)),
        Positioned(
            bottom: -140,
            right: -80,
            child: _blob(360, const Color(0xFF6EA8FF), .40)),
        Positioned(
            bottom: 40, left: 120, child: _blob(200, const Color(0xFF9DD5FF), .22)),

        // Draggable strip + close button (window has no OS title bar).
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 44,
          child: DragToMoveArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Obx(() => _CloseButton(
                      onTap: btnEnabled.value
                          ? () => windowManager.close()
                          : null,
                    )),
              ],
            ),
          ),
        ),

        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 56),
            child: _glassCard(),
          ),
        ),
      ],
    );
  }

  Widget _blob(double size, Color color, double opacity) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(opacity), color.withOpacity(0)],
          ),
        ),
      ),
    );
  }

  Widget _glassCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 460,
          padding: const EdgeInsets.fromLTRB(40, 40, 40, 32),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.78),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.65)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 48,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Obx(
            () => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset('assets/bydesk_logo.svg', height: 32),
                const SizedBox(height: 10),
                Text(
                  translate(_kTagline),
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withOpacity(0.45),
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: showProgress.value ? _installing() : _idle(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- installing state -------------------------------------------------

  Widget _installing() {
    return Column(
      key: const ValueKey('installing'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${translate('Installing')} $appName...',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 6,
            backgroundColor: Colors.black.withOpacity(0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(_kBrand),
          ),
        ),
        const SizedBox(height: 14),
        Obx(
          () => AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              '${translate(_stages[stageIndex.value])}...',
              key: ValueKey<int>(stageIndex.value),
              style:
                  TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.45)),
            ),
          ),
        ),
      ],
    );
  }

  // ---- idle state -------------------------------------------------------

  Widget _idle() {
    return Column(
      key: const ValueKey('idle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton(
            onPressed: btnEnabled.value ? install : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBrand,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(translate('Install')),
          ),
        ),
        const SizedBox(height: 10),
        _customizeToggle(),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: showAdvanced.value
              ? _advancedOptions()
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 18),
        _agreementLine(),
        if (!bind.installShowRunWithoutInstall()) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed:
                btnEnabled.value ? () => bind.installRunWithoutInstall() : null,
            style: TextButton.styleFrom(
              foregroundColor: Colors.black.withOpacity(0.45),
              textStyle: const TextStyle(fontSize: 12),
            ),
            child: Text(translate('Run without install')),
          ),
        ],
      ],
    );
  }

  Widget _customizeToggle() {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: btnEnabled.value
          ? () => showAdvanced.value = !showAdvanced.value
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              translate('Customize installation'),
              style: TextStyle(
                fontSize: 12.5,
                color: _kBrand.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 3),
            AnimatedRotation(
              turns: showAdvanced.value ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 17, color: _kBrand.withOpacity(0.9)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedOptions() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            translate('Installation Path'),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Colors.black.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  readOnly: true,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Colors.black.withOpacity(0.08)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: Colors.black.withOpacity(0.08)),
                    ),
                  ),
                ).workaroundFreezeLinuxMint(),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: btnEnabled.value ? selectInstallPath : null,
                style: TextButton.styleFrom(
                  foregroundColor: _kBrand,
                  textStyle: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
                child: Text(translate('Change Path')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _option(startmenu, 'Create start menu shortcuts'),
          _option(desktopicon, 'Create desktop icon'),
          _option(printer, 'Install {$appName} Printer'),
        ],
      ),
    );
  }

  Widget _option(RxBool option, String label) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => btnEnabled.value ? option.value = !option.value : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Obx(
              () => SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  visualDensity:
                      const VisualDensity(horizontal: -4, vertical: -4),
                  activeColor: _kBrand,
                  value: option.value,
                  onChanged: (v) =>
                      btnEnabled.value ? option.value = !option.value : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                translate(label),
                style: const TextStyle(fontSize: 12.5, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _agreementLine() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '${translate('agreement_tip')} ',
          style: TextStyle(fontSize: 11.5, color: Colors.black.withOpacity(0.45)),
        ),
        InkWell(
          hoverColor: Colors.transparent,
          onTap: () => launchUrlString('https://bydesk.app/privacy'),
          child: Tooltip(
            message: 'https://bydesk.app/privacy',
            child: Text(
              translate('End-user license agreement'),
              style: TextStyle(
                fontSize: 11.5,
                color: _kBrand.withOpacity(0.9),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- actions ----------------------------------------------------------

  void install() {
    btnEnabled.value = false;
    showAdvanced.value = false;
    showProgress.value = true;

    stageIndex.value = 0;
    _stageTimer?.cancel();
    _stageTimer = Timer.periodic(const Duration(milliseconds: 1600), (t) {
      if (stageIndex.value < _stages.length - 1) {
        stageIndex.value++;
      } else {
        t.cancel();
      }
    });

    String args = '';
    if (startmenu.value) args += ' startmenu';
    if (desktopicon.value) args += ' desktopicon';
    if (printer.value) args += ' printer';
    bind.installInstallMe(options: args, path: controller.text);
  }

  void selectInstallPath() async {
    String? install_path = await FilePicker.platform
        .getDirectoryPath(initialDirectory: controller.text);
    if (install_path != null) {
      controller.text = join(install_path, await bind.mainGetAppName());
    }
  }
}

class _CloseButton extends StatefulWidget {
  const _CloseButton({this.onTap});
  final VoidCallback? onTap;

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 44,
          height: 44,
          color: _hover && enabled ? Colors.white.withOpacity(0.16) : null,
          child: Icon(
            Icons.close_rounded,
            size: 17,
            color: Colors.white.withOpacity(enabled ? 0.85 : 0.35),
          ),
        ),
      ),
    );
  }
}
