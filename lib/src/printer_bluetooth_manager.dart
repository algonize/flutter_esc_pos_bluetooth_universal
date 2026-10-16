import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' show License;
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

import 'enums.dart';
import 'models/ble_printer_service.dart';
import 'models/bluetooth_capabilities.dart';
import 'models/bluetooth_printer.dart';
import 'models/bluetooth_write_options.dart';
import 'models/print_ticket.dart';
import 'platform/bluetooth_platform.dart';
import 'platform/bluetooth_platform_io.dart'
    if (dart.library.js_interop) 'platform/bluetooth_platform_web.dart'
    as platform;
import 'print_session.dart';
import 'printer_bluetooth_interface.dart';
import 'raster/widget_raster.dart';
import 'transport/printer_transport.dart';

/// Finds, connects to and prints on ESC/POS Bluetooth printers, BLE and
/// Classic, with the same code on Android, iOS, macOS, Windows, Linux and web.
///
/// ```dart
/// final manager = PrinterBluetoothManager(license: License.nonprofit);
/// await manager.selectPrinter(printer);        // from a scan, a list or the web chooser
/// final result = await manager.printWidget(context, child: const MyReceipt());
/// ```
///
/// [license] is passed to flutter_blue_plus for BLE connections. Choose the
/// value that matches you under the FlutterBluePlus License:
/// [License.nonprofit] for personal, nonprofit and educational use, and
/// [License.commercial] for any for-profit use (a paid licence from the
/// flutter_blue_plus authors).
class PrinterBluetoothManager implements BasePrinterBluetoothManager {
  PrinterBluetoothManager({
    required this._license,
    this._paperSize = ThermalPosPrinterPageSize.size80mm,
    this._profile,
    this._timeout = const Duration(seconds: 20),
    this._writeOptions = const BluetoothWriteOptions(),
    this._bleServices = defaultBlePrinterServices,
    BluetoothPrinter? printer,
  }) : _selectedPrinter = printer;

  static final BluetoothPlatform _platform = platform.createBluetoothPlatform();

  final License _license;
  final ThermalPosPrinterPageSize _paperSize;
  CapabilityProfile? _profile;
  final Duration _timeout;
  final BluetoothWriteOptions _writeOptions;
  final List<BlePrinterService> _bleServices;

  BluetoothPrinter? _selectedPrinter;
  PrinterTransport? _transport;
  PrintSession? _session;
  bool _isPrinting = false;
  Object? _lastError;
  PrintOutcome? _lastPrint;

  final _statusController = StreamController<BluetoothConnectionStatus>.broadcast();
  BluetoothConnectionStatus _status = BluetoothConnectionStatus.disconnected;

  // ── Platform ───────────────────────────────────────────────────────────────

  /// What this platform supports: BLE, Classic, scanning or a browser chooser.
  static BluetoothCapabilities get capabilities => _platform.capabilities;

  /// Whether Bluetooth is on and usable.
  Future<BluetoothAvailability> checkAvailability() => _platform.availability();

  /// Asks for Bluetooth permissions (Android 12+). Returns whether they are granted.
  Future<bool> requestPermissions() => _platform.requestPermissions();

  // ── Discovery ──────────────────────────────────────────────────────────────

  /// Printers found by the current or last scan. Paired printers first, then
  /// by signal strength.
  Stream<List<BluetoothPrinter>> get scanResults => _platform.scanResults;

  List<BluetoothPrinter> get lastScanResults => _platform.lastScanResults;

  Stream<bool> get isScanningStream => _platform.isScanning;

  bool get isScanning => _platform.isScanningNow;

  /// Scans for nearby printers for [timeout]. Native platforms only; on the web
  /// use [requestPrinter]. Results arrive on [scanResults].
  ///
  /// Unnamed BLE devices are skipped unless [includeUnnamed] is true, as real
  /// printers always advertise a name and the rest is noise.
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 8),
    Set<BluetoothPrinterType> types = const {
      BluetoothPrinterType.ble,
      BluetoothPrinterType.classic,
    },
    bool includeUnnamed = false,
  }) {
    return _platform.startScan(
      timeout: timeout,
      types: types,
      bleServices: _bleServices,
      includeUnnamed: includeUnnamed,
    );
  }

  Future<void> stopScan() => _platform.stopScan();

  /// Printers usable without scanning: paired Classic printers on native
  /// platforms, or Bluetooth serial ports this page may already use on the web.
  Future<List<BluetoothPrinter>> pairedPrinters() => _platform.pairedPrinters();

  /// Web only: opens the browser's Bluetooth chooser and selects the printer
  /// picked there. Call it from a button tap; browsers block it otherwise.
  /// Returns null when the chooser is closed without a choice.
  ///
  /// [BluetoothPrinterType.ble] uses Web Bluetooth.
  /// [BluetoothPrinterType.classic] uses Web Serial (paired printers, desktop Chrome 117+).
  Future<BluetoothPrinter?> requestPrinter({
    BluetoothPrinterType type = BluetoothPrinterType.ble,
  }) async {
    final printer = await _platform.requestPrinter(type: type, bleServices: _bleServices);
    if (printer != null) await selectPrinter(printer);
    return printer;
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  /// The printer used by [connect] and the print methods. After a successful
  /// connection it also carries what was learned (the BLE write
  /// characteristic, or on macOS the BLE side of a Classic printer), so save
  /// this one rather than the scan result.
  BluetoothPrinter? get selectedPrinter => _selectedPrinter;

  /// Chooses the printer to print on. Disconnects from a different one first.
  Future<void> selectPrinter(BluetoothPrinter printer) async {
    if (_selectedPrinter == printer) {
      // The same device: keep the characteristic learned on a connection
      // when the new copy does not carry one.
      _selectedPrinter = printer.serviceUuid == null && _selectedPrinter?.serviceUuid != null
          ? _selectedPrinter
          : printer;
      return;
    }
    await disconnect();
    _selectedPrinter = printer;
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  Stream<BluetoothConnectionStatus> get connectionStatus => _statusController.stream;

  BluetoothConnectionStatus get status => _status;

  @override
  bool get isConnected => _transport?.isConnected ?? false;

  /// The underlying error behind the last failed connect or print, for logs and
  /// bug reports. The returned [PosPrintResult] is the user-facing summary.
  Object? get lastError => _lastError;

  /// How the last ticket was sent: its size, time and rate. For logs.
  PrintOutcome? get lastPrint => _lastPrint;

  @override
  ThermalPosPrinterPageSize get paperSize => _paperSize;

  @override
  CapabilityProfile? get profile => _profile;

  @override
  Future<PosPrintResult> connect({Duration? timeout}) async {
    final printer = _selectedPrinter;
    if (printer == null) return PosPrintResult.printerNotSelected;
    if (isConnected) return PosPrintResult.success;
    _lastError = null;

    // Connecting while scanning is unreliable on Android, so stop the scan.
    if (isScanning) await stopScan();

    // Web Serial ports are only known for this page session: re-list the ports
    // the page was allowed to use, so a saved Classic printer can reconnect.
    if (capabilities.chooser && printer.isClassic) await pairedPrinters();

    _setStatus(BluetoothConnectionStatus.connecting);
    try {
      _profile ??= await CapabilityProfile.load();
      final transport = _platform.createTransport(
        printer,
        license: _license,
        options: _writeOptions,
        bleServices: _bleServices,
      );
      await transport.connect(timeout ?? _timeout);
      _transport = transport;
      _selectedPrinter = transport.printer;
      _session = PrintSession(
        transport: transport,
        pacing: _writeOptions.pacing,
        // Paced to the paper width: a millimetre of raster is widthPx bytes.
        widthDots: _paperSize.widthPx.toInt(),
      );
      _setStatus(BluetoothConnectionStatus.connected);
      return PosPrintResult.success;
    } on PrinterTransportException catch (e) {
      _lastError = e.cause ?? e;
      _setStatus(BluetoothConnectionStatus.disconnected);
      return e.result;
    } catch (e) {
      _lastError = e;
      _setStatus(BluetoothConnectionStatus.disconnected);
      return PosPrintResult.connectionFailed;
    }
  }

  @override
  Future<PosPrintResult> disconnect({Duration? timeout}) async {
    final transport = _transport;
    _transport = null;
    _session = null;
    if (transport == null) return PosPrintResult.success;
    _setStatus(BluetoothConnectionStatus.disconnecting);
    try {
      await transport.disconnect();
      if (timeout != null) await Future<void>.delayed(timeout);
      return PosPrintResult.success;
    } catch (_) {
      return PosPrintResult.disconnectError;
    } finally {
      _setStatus(BluetoothConnectionStatus.disconnected);
    }
  }

  // ── Printing ───────────────────────────────────────────────────────────────

  /// Sends raw ESC/POS [data], connecting first when needed.
  ///
  /// Disconnects afterwards unless [isDisconnect] is false, which keeps the
  /// link open for more tickets (call [disconnect] when done).
  @override
  Future<PosPrintResult> printTicket(List<int> data, {bool isDisconnect = true}) {
    if (data.isEmpty) return Future.value(PosPrintResult.ticketEmpty);
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    return _print(PrintTicket(bytes), isDisconnect: isDisconnect);
  }

  /// Renders [child] as an image and prints it, connecting first when needed.
  /// Handy for logos, QR codes, barcodes, non-Latin scripts and rich layouts.
  /// The image goes as `ESC *` column bands, as the network package sends it.
  ///
  /// [gapMm] adds that much blank paper below the receipt, for tearing by
  /// hand on printers without a cutter (most Bluetooth receipt printers).
  @override
  Future<PosPrintResult> printWidget(
    BuildContext context, {
    required Widget child,
    bool isDisconnect = true,
    double gapMm = 0,
  }) async {
    if (_isPrinting) return PosPrintResult.printInProgress;
    if (_selectedPrinter == null) return PosPrintResult.printerNotSelected;
    final PrintTicket ticket;
    try {
      final profile = _profile ??= await CapabilityProfile.load();
      if (!context.mounted) return PosPrintResult.unknown;
      ticket = await buildWidgetTicket(
        context,
        child,
        paperSize: _paperSize,
        profile: profile,
        gapMm: gapMm,
      );
    } catch (e) {
      // Rendering failed, for example a widget that can't lay out at paper width.
      _lastError = e;
      return PosPrintResult.ticketEmpty;
    }
    if (ticket.isEmpty) return PosPrintResult.ticketEmpty;
    return _print(ticket, isDisconnect: isDisconnect);
  }

  Future<PosPrintResult> _print(PrintTicket ticket, {required bool isDisconnect}) async {
    if (_isPrinting) return PosPrintResult.printInProgress;
    _isPrinting = true;
    try {
      if (!isConnected) {
        final result = await connect();
        if (result != PosPrintResult.success) return result;
      }
      final outcome = await _session!.send(ticket);
      _lastPrint = outcome;
      if (kDebugMode) {
        debugPrint(
          'flutter_esc_pos_bluetooth_universal: $outcome, '
          '${_writeOptions.pacing ?? 'no pacing'}, ${_paperSize.widthPx.toInt()} dots',
        );
      }
      return PosPrintResult.success;
    } on PrinterTransportException catch (e) {
      _lastError = e.cause ?? e;
      await disconnect();
      return e.result;
    } catch (e) {
      _lastError = e;
      await disconnect();
      return PosPrintResult.writeFailed;
    } finally {
      if (isDisconnect) await disconnect();
      _isPrinting = false;
    }
  }

  /// Disconnects and releases this manager. Don't use it afterwards.
  Future<void> dispose() async {
    await disconnect();
    await _statusController.close();
  }

  void _setStatus(BluetoothConnectionStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }
}
