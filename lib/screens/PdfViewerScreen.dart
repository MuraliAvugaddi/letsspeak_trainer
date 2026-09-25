import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

class PdfViewerScreen extends StatefulWidget {
  final String fileName;
  final String stageFolder;

  const PdfViewerScreen({
    super.key,
    required this.fileName,
    required this.stageFolder,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  // ============================================================
  // LETSSPEAK BRAND COLORS
  // ============================================================

  static const Color navy = Color(0xFF155A88);
  static const Color deepNavy = Color(0xFF0E466D);
  static const Color blue = Color(0xFF2C6F9F);

  static const Color teal = Color(0xFF28C2C2);
  static const Color yellow = Color(0xFFF7DF55);
  static const Color periwinkle = Color(0xFF7CA4D8);

  static const Color background = Color(0xFFE8F2F8);
  static const Color backgroundDark = Color(0xFFD9EAF3);

  static const Color errorRed = Color(0xFFE45757);

  String? localPdfPath;

  bool isLoading = true;

  String errorMessage = '';

  int currentPage = 0;

  int totalPages = 0;

  @override
  void initState() {
    super.initState();

    _loadPdfFromAsset();
  }

  // ============================================================
  // LOAD PDF
  // ============================================================

  Future<void> _loadPdfFromAsset() async {
    try {
      String cleanFileName = widget.fileName.trim();

      if (cleanFileName.toLowerCase().endsWith('.pdf')) {
        cleanFileName = cleanFileName.substring(0, cleanFileName.length - 4);
      }

      String folder = widget.stageFolder.trim();

      // Only remap English folders; preserve Hindi nested directory structures intact
      if (!folder.toLowerCase().contains('hindi')) {
        String cleanFolder = folder.toLowerCase().replaceAll(' ', '');
        if (cleanFolder == 'stage1') {
          folder = 'satge1';
        } else if (cleanFolder == 'stage2') {
          folder = 'satge2';
        } else if (cleanFolder == 'stage3') {
          folder = 'satge3';
        } else if (cleanFolder == 'stage4') {
          folder = 'stage4';
        }
      }

      final String assetPath = 'assets/images/$folder/$cleanFileName.pdf';

      debugPrint('Attempting to load PDF from asset: $assetPath');

      final ByteData data = await rootBundle.load(assetPath);

      final List<int> bytes = data.buffer.asUint8List();

      final Directory tempDir = await getTemporaryDirectory();

      final File tempFile = File('${tempDir.path}/$cleanFileName.pdf');

      await tempFile.writeAsBytes(bytes, flush: true);

      if (!mounted) return;

      setState(() {
        localPdfPath = tempFile.path;
        isLoading = false;
        errorMessage = '';
      });
    } catch (e) {
      debugPrint('PDF Load Error: $e');

      if (!mounted) return;

      setState(() {
        errorMessage =
            'We could not open this PDF.\n\n'
            'Please check that the file exists '
            'inside the selected stage folder.\n\n'
            'Error: $e';

        isLoading = false;
      });
    }
  }

  // ============================================================
  // RELOAD
  // ============================================================

  Future<void> _reloadPdf() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
      localPdfPath = null;
      currentPage = 0;
      totalPages = 0;
    });

    await _loadPdfFromAsset();
  }

  // ============================================================
  // MAIN BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;

    final bool isDesktop = width >= 900;

    return Scaffold(
      backgroundColor: background,

      appBar: _buildAppBar(context, isDesktop),

      body: isLoading
          ? _buildLoadingScreen()
          : errorMessage.isNotEmpty
          ? _buildErrorScreen()
          : _buildPdfScreen(isDesktop),
    );
  }

  // ============================================================
  // APP BAR
  // ============================================================

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDesktop) {
    return AppBar(
      elevation: 0,

      scrolledUnderElevation: 0,

      backgroundColor: navy,

      toolbarHeight: isDesktop ? 68 : 62,

      leading: Padding(
        padding: const EdgeInsets.only(left: 10, top: 10, bottom: 10),

        child: Material(
          color: Colors.white.withValues(alpha: 0.12),

          borderRadius: BorderRadius.circular(13),

          child: InkWell(
            borderRadius: BorderRadius.circular(13),

            onTap: () {
              Navigator.pop(context);
            },

            child: const Icon(
              Icons.arrow_back_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),

      titleSpacing: 14,

      title: Row(
        children: [
          // ======================================================
          // PDF ICON
          // ======================================================
          Container(
            width: 42,
            height: 42,

            decoration: BoxDecoration(
              color: teal,

              borderRadius: BorderRadius.circular(13),

              boxShadow: [
                BoxShadow(
                  color: teal.withValues(alpha: 0.25),

                  blurRadius: 14,

                  offset: const Offset(0, 5),
                ),
              ],
            ),

            child: const Icon(
              Icons.picture_as_pdf_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),

          const SizedBox(width: 12),

          // ======================================================
          // PDF TITLE
          // ======================================================
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              mainAxisAlignment: MainAxisAlignment.center,

              children: [
                Text(
                  widget.fileName,

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                  style: GoogleFonts.poppins(
                    color: Colors.white,

                    fontSize: isDesktop ? 15 : 13,

                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 1),

                Row(
                  children: [
                    Text(
                      _formatStage(widget.stageFolder),

                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.72),

                        fontSize: 10,

                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    if (totalPages > 0) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 7),

                        width: 4,
                        height: 4,

                        decoration: const BoxDecoration(
                          color: yellow,
                          shape: BoxShape.circle,
                        ),
                      ),

                      Text(
                        '$totalPages pages',

                        style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.72),

                          fontSize: 10,

                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // ======================================================
          // RELOAD BUTTON
          // ======================================================
          Material(
            color: Colors.white.withValues(alpha: 0.10),

            borderRadius: BorderRadius.circular(12),

            child: InkWell(
              borderRadius: BorderRadius.circular(12),

              onTap: isLoading ? null : _reloadPdf,

              child: const Padding(
                padding: EdgeInsets.all(10),

                child: Icon(
                  Icons.refresh_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),

          const SizedBox(width: 10),
        ],
      ),
    );
  }

  // ============================================================
  // LOADING
  // ============================================================

  Widget _buildLoadingScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,

          colors: [background, backgroundDark],
        ),
      ),

      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 390),

          margin: const EdgeInsets.all(24),

          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 32),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(26),

            border: Border.all(color: navy.withValues(alpha: 0.10)),

            boxShadow: [
              BoxShadow(
                color: navy.withValues(alpha: 0.13),

                blurRadius: 35,

                offset: const Offset(0, 14),
              ),
            ],
          ),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              // ==================================================
              // LOGO STYLE ICON
              // ==================================================
              Container(
                width: 78,
                height: 78,

                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,

                    colors: [navy, blue],
                  ),

                  borderRadius: BorderRadius.circular(24),
                ),

                child: Stack(
                  alignment: Alignment.center,

                  children: [
                    const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 34,
                    ),

                    Positioned(
                      bottom: 14,
                      right: 15,

                      child: Container(
                        width: 9,
                        height: 9,

                        decoration: const BoxDecoration(
                          color: yellow,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              Text(
                'Opening your material',

                style: GoogleFonts.poppins(
                  color: navy,

                  fontSize: 18,

                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 7),

              Text(
                'Preparing your learning document...',
                textAlign: TextAlign.center,

                style: GoogleFonts.poppins(
                  color: navy.withValues(alpha: 0.58),

                  fontSize: 12,

                  height: 1.5,
                ),
              ),

              const SizedBox(height: 20),

              // ==================================================
              // BRAND LOADING BAR
              // ==================================================
              Container(
                height: 5,
                width: 180,

                decoration: BoxDecoration(
                  color: periwinkle.withValues(alpha: 0.18),

                  borderRadius: BorderRadius.circular(10),
                ),

                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,

                  widthFactor: 0.55,

                  child: Container(
                    decoration: BoxDecoration(
                      color: teal,

                      borderRadius: BorderRadius.circular(10),
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

  // ============================================================
  // ERROR SCREEN
  // ============================================================

  Widget _buildErrorScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,

          colors: [background, backgroundDark],
        ),
      ),

      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),

          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),

            padding: const EdgeInsets.all(30),

            decoration: BoxDecoration(
              color: Colors.white,

              borderRadius: BorderRadius.circular(26),

              border: Border.all(color: errorRed.withValues(alpha: 0.15)),

              boxShadow: [
                BoxShadow(
                  color: navy.withValues(alpha: 0.13),

                  blurRadius: 35,

                  offset: const Offset(0, 14),
                ),
              ],
            ),

            child: Column(
              mainAxisSize: MainAxisSize.min,

              children: [
                Container(
                  width: 76,
                  height: 76,

                  decoration: BoxDecoration(
                    color: errorRed.withValues(alpha: 0.10),

                    borderRadius: BorderRadius.circular(23),
                  ),

                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: errorRed,
                    size: 34,
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Unable to open document',

                  textAlign: TextAlign.center,

                  style: GoogleFonts.poppins(
                    color: navy,

                    fontSize: 19,

                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  errorMessage,

                  textAlign: TextAlign.center,

                  style: GoogleFonts.poppins(
                    color: navy.withValues(alpha: 0.58),

                    fontSize: 11.5,

                    height: 1.55,
                  ),
                ),

                const SizedBox(height: 24),

                // =================================================
                // TRY AGAIN
                // =================================================
                SizedBox(
                  width: double.infinity,
                  height: 50,

                  child: ElevatedButton.icon(
                    onPressed: _reloadPdf,

                    icon: const Icon(Icons.refresh_rounded, size: 20),

                    label: Text(
                      'Try again',

                      style: GoogleFonts.poppins(
                        fontSize: 13,

                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    style: ElevatedButton.styleFrom(
                      backgroundColor: teal,

                      foregroundColor: Colors.white,

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // =================================================
                // GO BACK
                // =================================================
                SizedBox(
                  width: double.infinity,
                  height: 48,

                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },

                    style: OutlinedButton.styleFrom(
                      foregroundColor: navy,

                      side: BorderSide(
                        color: navy.withValues(alpha: 0.18),

                        width: 1.2,
                      ),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),

                    child: Text(
                      'Go back',

                      style: GoogleFonts.poppins(
                        fontSize: 12.5,

                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PDF SCREEN
  // ============================================================

  Widget _buildPdfScreen(bool isDesktop) {
    return Container(
      color: background,

      child: Stack(
        children: [
          // ======================================================
          // PDF PAPER (Filled cleanly without gap alignment issues)
          // ======================================================
          Positioned.fill(
            child: Container(
              margin: EdgeInsets.symmetric(
                horizontal: isDesktop ? 30 : 0,
                vertical: isDesktop ? 12 : 0,
              ),

              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.circular(isDesktop ? 20 : 0),

                border: Border.all(color: navy.withValues(alpha: 0.12)),

                boxShadow: isDesktop
                    ? [
                        BoxShadow(
                          color: navy.withValues(alpha: 0.14),

                          blurRadius: 35,

                          offset: const Offset(0, 14),
                        ),
                      ]
                    : null,
              ),

              clipBehavior: Clip.antiAlias,

              child: PDFView(
                filePath: localPdfPath!,

                enableSwipe: true,

                swipeHorizontal: false,

                autoSpacing: true,

                pageFling: true,

                pageSnap: true,

                defaultPage: 0,

                fitPolicy: FitPolicy.BOTH,

                onRender: (pages) {
                  if (!mounted) return;

                  setState(() {
                    totalPages = pages ?? 0;
                  });
                },

                onPageChanged: (page, total) {
                  if (!mounted) return;

                  setState(() {
                    currentPage = page ?? 0;

                    totalPages = total ?? totalPages;
                  });
                },

                onError: (error) {
                  debugPrint('PDF Render Error: $error');
                },

                onPageError: (page, error) {
                  debugPrint('PDF Page $page Error: $error');
                },
              ),
            ),
          ),

          // ======================================================
          // PAGE INDICATOR
          // ======================================================
          if (totalPages > 0)
            Positioned(
              bottom: isDesktop ? 24 : 18,

              left: 0,
              right: 0,

              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 9,
                    ),

                    decoration: BoxDecoration(
                      color: navy,

                      borderRadius: BorderRadius.circular(30),

                      boxShadow: [
                        BoxShadow(
                          color: navy.withValues(alpha: 0.25),

                          blurRadius: 18,

                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),

                    child: Row(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        const Icon(
                          Icons.menu_book_rounded,

                          color: yellow,

                          size: 15,
                        ),

                        const SizedBox(width: 7),

                        Text(
                          'Page ${currentPage + 1} of $totalPages',

                          style: GoogleFonts.poppins(
                            color: Colors.white,

                            fontSize: 11,

                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // FORMAT STAGE NAME
  // ============================================================

  String _formatStage(String value) {
    // Clean up pathing values like "Hindi/stagehindiStage1" into clear friendly strings like "Hindi Stage 1"
    if (value.toLowerCase().contains('hindi')) {
      final regExp = RegExp(r'stage(\d+)', caseSensitive: false);
      final match = regExp.firstMatch(value);
      final stageNum = match != null ? match.group(1) : '1';
      return 'Hindi Stage $stageNum';
    }

    final String clean = value.replaceAll('_', ' ').replaceAll('-', ' ').trim();

    if (clean.isEmpty) {
      return 'Learning material';
    }

    return clean
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;

          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }
}
