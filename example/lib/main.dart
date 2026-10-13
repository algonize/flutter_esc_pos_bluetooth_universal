import 'package:flutter/material.dart';
import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth printer',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF19478D), useMaterial3: true),
      home: const PrinterPage(),
    );
  }
}

class PrinterPage extends StatefulWidget {
  const PrinterPage({super.key});

  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> {
  // Use License.commercial for any for-profit use (see the FlutterBluePlus License).
  late PrinterBluetoothManager _manager = _createManager();

  PrinterBluetoothManager _createManager([BluetoothPrinter? printer]) =>
      PrinterBluetoothManager(license: License.nonprofit, paperSize: _paperSize, printer: printer);

  ThermalPosPrinterPageSize _paperSize = ThermalPosPrinterPageSize.size80mm;
  List<BluetoothPrinter> _paired = const [];
  bool _busy = false;

  final _capabilities = PrinterBluetoothManager.capabilities;

  @override
  void initState() {
    super.initState();
    _loadPaired();
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  Future<void> _loadPaired() async {
    if (!_capabilities.pairedList) return;
    final paired = await _manager.pairedPrinters();
    if (mounted) setState(() => _paired = paired);
  }

  Future<void> _run(Future<PosPrintResult> Function() action) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    // On failure, show the underlying error too: it is what to report.
    final detail = result.isSuccess ? '' : '\n${_manager.lastError ?? ''}';
    if (!result.isSuccess) debugPrint('Print failed: ${result.name}: ${_manager.lastError}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.msg}$detail'), duration: const Duration(seconds: 8)),
    );
  }

  Future<PosPrintResult> _printTestTicket() async {
    final generator = Generator(_paperSize.toPaperSize, await CapabilityProfile.load());
    final bytes = <int>[
      ...generator.text(
        'ALGORAMMING CAFE',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2),
      ),
      ...generator.text('Bluetooth test ticket', styles: const PosStyles(align: PosAlign.center)),
      ...generator.hr(),
      ...generator.row([
        PosColumn(text: 'Espresso', width: 8),
        PosColumn(
          text: '3.00',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
      ...generator.row([
        PosColumn(text: 'Croissant', width: 8),
        PosColumn(
          text: '2.50',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]),
      ...generator.hr(),
      ...generator.text('Thank you!', styles: const PosStyles(align: PosAlign.center)),
      ...generator.feed(2),
      ...generator.cut(),
    ];
    return _manager.printTicket(bytes);
  }

  Future<void> _choose(BluetoothPrinterType type) async {
    // Must run straight from a tap: browsers only open the chooser for a user gesture.
    final printer = await _manager.requestPrinter(type: type);
    if (!mounted) return;
    if (printer == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(PosPrintResult.userCancelled.msg)));
    }
    setState(() {});
    await _loadPaired();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _manager.selectedPrinter;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth printer'),
        actions: [
          StreamBuilder<BluetoothConnectionStatus>(
            stream: _manager.connectionStatus,
            initialData: _manager.status,
            builder: (_, snapshot) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Chip(label: Text(snapshot.data!.name)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'BLE: ${_capabilities.ble ? 'yes' : 'no'}   ·   Classic: ${_capabilities.classic ? 'yes' : 'no'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SegmentedButton<ThermalPosPrinterPageSize>(
            segments: [
              for (final size in ThermalPosPrinterPageSize.values)
                ButtonSegment(value: size, label: Text(size.title)),
            ],
            selected: {_paperSize},
            onSelectionChanged: (s) {
              // The paper size is fixed per manager, so start a new one for the new size.
              final previous = _manager;
              setState(() {
                _paperSize = s.first;
                _manager = _createManager(previous.selectedPrinter);
              });
              previous.dispose();
            },
          ),
          const SizedBox(height: 16),
          if (_capabilities.chooser) ..._webPicker() else ..._nativeScanner(),
          if (_paired.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Paired or allowed', style: Theme.of(context).textTheme.titleMedium),
            for (final printer in _paired) _printerTile(printer),
          ],
          const Divider(height: 32),
          ListTile(
            title: Text(selected?.displayName ?? 'No printer selected'),
            subtitle: Text(
              selected == null ? 'Pick a printer above' : selected.type.name.toUpperCase(),
            ),
            leading: const Icon(Icons.print_outlined),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: selected == null || _busy ? null : () => _run(_printTestTicket),
                child: const Text('Print test ticket'),
              ),
              FilledButton.tonal(
                onPressed: selected == null || _busy
                    ? null
                    : () => _run(() => _manager.printWidget(context, child: const _Receipt())),
                child: const Text('Print widget'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(_manager.disconnect),
                child: const Text('Disconnect'),
              ),
            ],
          ),
          if (_busy)
            const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
        ],
      ),
    );
  }

  List<Widget> _webPicker() => [
    Text('Choose a printer', style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_capabilities.ble)
          FilledButton.icon(
            onPressed: () => _choose(BluetoothPrinterType.ble),
            icon: const Icon(Icons.bluetooth),
            label: const Text('BLE printer'),
          ),
        if (_capabilities.classic)
          FilledButton.icon(
            onPressed: () => _choose(BluetoothPrinterType.classic),
            icon: const Icon(Icons.cable),
            label: const Text('Classic printer (paired)'),
          ),
      ],
    ),
    if (!_capabilities.ble && !_capabilities.classic)
      const Text('Bluetooth printing needs Chrome or Edge on a computer or Android.'),
  ];

  List<Widget> _nativeScanner() => [
    Row(
      children: [
        Text('Nearby printers', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        StreamBuilder<bool>(
          stream: _manager.isScanningStream,
          initialData: _manager.isScanning,
          builder: (_, snapshot) => snapshot.data!
              ? TextButton(onPressed: _manager.stopScan, child: const Text('Stop'))
              : TextButton(
                  onPressed: () async {
                    final availability = await _manager.checkAvailability();
                    if (availability != BluetoothAvailability.available && mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Bluetooth is ${availability.name}')));
                      return;
                    }
                    await _manager.startScan();
                  },
                  child: const Text('Scan'),
                ),
        ),
      ],
    ),
    StreamBuilder<List<BluetoothPrinter>>(
      stream: _manager.scanResults,
      initialData: _manager.lastScanResults,
      builder: (_, snapshot) =>
          Column(children: [for (final printer in snapshot.data!) _printerTile(printer)]),
    ),
  ];

  Widget _printerTile(BluetoothPrinter printer) {
    final selected = _manager.selectedPrinter == printer;
    return ListTile(
      selected: selected,
      leading: Icon(printer.isBle ? Icons.bluetooth : Icons.print),
      title: Text(printer.displayName),
      subtitle: Text(
        [
          printer.type.name.toUpperCase(),
          if (printer.isPaired) 'paired',
          if (printer.rssi != null) '${printer.rssi} dBm',
        ].join(' · '),
      ),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: () async {
        await _manager.selectPrinter(printer);
        setState(() {});
      },
    );
  }
}

/// Any widget can be printed; it is rendered to an image first.
class _Receipt extends StatelessWidget {
  const _Receipt();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.black, fontSize: 22);
    return const Padding(
      padding: EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ALGORAMMING CAFE',
            style: TextStyle(color: Colors.black, fontSize: 30, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text('Printed from a Flutter widget', style: style),
          Divider(color: Colors.black),
          Row(
            children: [
              Expanded(child: Text('Latte', style: style)),
              Text('4.20', style: style),
            ],
          ),
          Row(
            children: [
              Expanded(child: Text('Muffin', style: style)),
              Text('2.80', style: style),
            ],
          ),
          Divider(color: Colors.black),
          Row(
            children: [
              Expanded(
                child: Text(
                  'TOTAL',
                  style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                '7.00',
                style: TextStyle(color: Colors.black, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
