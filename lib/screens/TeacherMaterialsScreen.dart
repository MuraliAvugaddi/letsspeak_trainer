import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:letsspeak_trainer/screens/PdfViewerScreen.dart';

class TeacherMaterialsScreen extends StatelessWidget {
  final Map<String, dynamic> teacherData;

  const TeacherMaterialsScreen({super.key, required this.teacherData});

  static const Color navy = Color(0xFF155A88);
  static const Color deepNavy = Color(0xFF0E466D);
  static const Color blue = Color(0xFF2C6F9F);
  static const Color teal = Color(0xFF28C2C2);
  static const Color yellow = Color(0xFFF7DF55);
  static const Color periwinkle = Color(0xFF7CA4D8);
  static const Color background = Color(0xFFE8F2F8);
  static const Color backgroundDark = Color(0xFFD9EAF3);
  static const Color white = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final String rawLanguage =
        (teacherData['language'] ?? teacherData['courseLanguage'] ?? 'english')
            .toString()
            .toLowerCase()
            .trim();
    final bool isHindi = rawLanguage.contains('hindi');

    final String rawStage =
        (teacherData['stage'] ?? teacherData['teacherStage'] ?? 'stage1')
            .toString()
            .toLowerCase()
            .replaceAll(' ', '');

    int stageNumber = 1;
    if (rawStage.contains('2')) {
      stageNumber = 2;
    } else if (rawStage.contains('3')) {
      stageNumber = 3;
    } else if (rawStage.contains('4')) {
      stageNumber = 4;
    } else if (rawStage.contains('5')) {
      stageNumber = 5;
    } else if (rawStage.contains('6')) {
      stageNumber = 6;
    } else if (rawStage.contains('7')) {
      stageNumber = 7;
    }

    final String assignedStageKey = 'Stage $stageNumber';

    String stageFolder = '';
    if (isHindi) {
      if (stageNumber == 1) {
        stageFolder = 'Hindi/stagehindiStage1';
      } else {
        stageFolder = 'Hindi/stagehindistage$stageNumber';
      }
    } else {
      stageFolder = stageNumber == 1
          ? 'satge1'
          : (stageNumber == 2
                ? 'satge2'
                : (stageNumber == 3 ? 'satge3' : 'stage4'));
    }

    final Map<String, Map<String, List<String>>> allNotes = {
      'English': {
        'Stage 1': [
          'Day-2_English_ST-1_(Past Be)',
          'Day-3_English_ST-1 (Past Be)',
          'Day-4_English_ST-1 (Pre Be)',
          'Day-5_English_ST-1 (Future Be)',
          'Day-6_ST-1_Eng (Articles & Practice On Be)',
          'Day-7_ST-1_Eng (There Form)',
          'Day-8_ST-1_Eng (Past Have)',
          'Day-9_ST-1_Eng (Present Have)',
          'Day-10_ST-1_Eng (Future Have)',
          'Day-11_ST-1_Eng (🔴Practice On Be, There & Have)',
          'Day-12_ST-1_Eng (Formation Of Action Verbs)',
          'Day-13_ST-1_Eng (Past Simple A.V)',
          'Day-14_ST-1_Eng (Present Simple A.V)',
          'Day-15_ST-1_Eng (Future Simple A.V)',
          'Day-16_ST-1_Eng (🔴Practice On Simple A.v)',
          'Day-17_ST-1_Eng (Past Simple Passive Voice)',
          'Day-18_ST-1_Eng (Present Simple P.V)',
          'Day-19_ST-1_Eng (Future Simple P.V)',
          'Day-21_ST-1_Eng (Past Continuous A.V & P.V)',
          'Day-22_ST-1_Eng (Present Continuous A.V & P.V)',
          'Day-23_ST-1_Eng (Future Continuous A.v)',
          'Day-24_ST-1_Eng (🔴Practice on Simple & Continuous A.v & P.v)',
          'Day-25_ST-1_Eng (Past Simple Make, Let & Get-Causative verbs)',
          'Day-26_ST-1_Eng (Present Simple M.L.G)',
          'Day-27_ST-1_Eng (Future Simple M.L.G)',
          'Day-28_ST-1_Eng (Past & Present Continuous M.L.G)',
        ],
        'Stage 2': [
          'Day-2_ST-2_Eng (Order-1&2)',
          'Day-3_ST-2_Eng (Request-1&2)',
          'Day-4_ST-2_Eng (Permission 1&2)',
          'Day-5_ST-2_Eng (Suggestion 1&2)',
          'Day-6_ST-2_Eng (🔴Practice on Imperative sentences)',
          'Day-7_ST-2_Eng (Past habit-1)',
          'Day-8_ST-2_Eng (Past habit-2,3 & 4)',
          'Day-9_ST-2_Eng (Present habit-2,3 & 4)',
          'Day-10_ST-2_Eng (Future habit-2 & 4)',
          'Day-11_ST-2_Eng (Past permanent ability comparison with past simple)',
          'Day-12_ST-2_Eng (Past temporary ability comparison with past continuous)',
          'Day-13_ST-2_Eng (Present permanent ability comparison with present simple)',
          'Day-14_ST-2_Eng (Present temporary ability comparison with Present continuous)',
          'Day-15_ST-2_Eng (Future permanent & temporary ability comparison with future simple & continuous)',
          'Day-16_ST-2_Eng (🔴 Practice on Ability, Simple & Continuous)',
          'Day-17_ST-2_Eng (Past willingness-1)',
          'Day-18_ST-2_Eng (Past willingness-2)',
          'Day-19_ST-2_Eng (Present willingness-1)',
          'Day-20_ST-2_Eng (Present willingness-2)',
          'Day-21_ST-2_Eng (🔴Practice on Past & Present willingness-1&2)',
          'Day-22_ST-2_Eng (Past, Present & Future willingness-3)',
          'Day-23_ST-2_Eng (Past, Present & Future compulsion)',
          'Day-24_ST-2_Eng (Lower modals)',
          'Day-25_ST-2_Eng (Integration of lower modals)',
          'Day-26_ST-2_Eng (Integration of would [used to])',
          'Day-27_ST-2_Eng (Gerund)',
          'Day-28_ST-2_Eng (It function)',
        ],
        'Stage 3': [
          'Day-2_ST-3_Eng (The Conjunctions of If & Unless)',
          'Day-3_ST-3_Eng (The conjunctions of When,Only When & While)',
          'Day-4_ST-3_Eng (🔴 Practice on If, Unless, When, Only When & While)',
          'Day-5_ST-3_Eng (The conjunctions of Before & After)',
          'Day-6_ST-3_Eng (The conjunctions of As soon as, As long as & Till [Until])',
          'Day-7_ST-3_Eng (🔴 Practice on Time conjunctions)',
          'Day-8_ST-3_Eng (The conjunctions of reasons But, So, Since_As...)',
          'Day-9_ST-3_Eng (🔴 Practice on conjunctions of reasons)',
          'Day-10_ST-3_Eng (Conjunctions of ever family)',
          'Day-11_ST-3_Eng (🔴Practice on all the conjunctions)',
          'Day-12_ST-3_Eng (Present perfect BE FORM)',
          'Day-13_ST-3_Eng (Present Perfect THERE FORM)',
          'Day-14_ST-3_Eng (Present Perfect IT FORM)',
          'Day-15_ST-3_Eng (Present Perfect HAVE FORM)',
          'Day-16_ST-3_Eng (🔴 Practice on Present Perfect BE, THERE, IT & HAVE forms)',
          'Day-17_ST-3_Eng (Present Perfect A.V)',
          'Day-18_ST-3_Eng (Present Perfect P.V)',
          'Day-19_ST-3_Eng (Present Perfect Continuous A.V)',
          'Day-20_ST-3_Eng (🔴 Practice on Present Perfect & Simple tenses)',
          'Day-21_ST-3_Eng (Past Perfect BE FORM)',
          'Day-22_ST-3_Eng (Past Perfect HAVE FORM)',
          'Day-23_ST-3_Eng (Past Perfect ACTIVE VOICE)',
          'Day-24_ST-3_Eng (Past Perfect PASSIVE VOICE)',
          'Day-25_ST-3_Eng (Past Perfect Continuous A.V)',
          'Day-26_ST-3_Eng (🔴Practice on the whole Past Perfect tense)',
          'Day-27_ST-3_Eng (Future Perfect BE & HAVE form)',
          'Day-28_ST-3_Eng (Future Perfect A.V & P.V)',
        ],
        'Stage 4': [
          'Day-2_ST-4_Eng (Higher modal-1)',
          'Day-3_ST-4_Eng (Higher modal-2)',
          'Day-4_ST-4_Eng (Higher modal-3,4 & 5)',
          'Day-5_ST-4_Eng (Integration of higher modals)',
          'Day-6_ST-4_Eng (🔴 Practice on Integration of higher modals)',
          'Day-7_ST-4_Eng (0-Condition)',
          'Day-8_ST-4_Eng (Real-Condition)',
          'Day-9_ST-4_Eng (Unfulfilled- Condition)',
          'Day-10_ST-4_Eng (Imaginary- Condition)',
          'Day-11_ST-4_Eng (🔴 Practice on conditional clauses)',
          'Day-12_ST-4_Eng (Adjectives followed by prepositions)',
          'Day-13_ST-4_Eng (Verbs followed by prepositions)',
          'Day-14_ST-4_Eng (Phrasal verbs)',
          'Day-15_ST-4_Eng (Phrasal Prepositions)',
          'Day-16_ST-4_Eng (Exclamatory sentences)',
          'Day-17_ST-4_Eng (WH +Statement of simple & perfect tenses)',
          'Day-18_ST-4_Eng (Question tags of simple & perfect tenses)',
          'Day-19_ST-4_Eng (Also, Too & Either of simple & perfect tenses)',
          'Day-20_ST-4_Eng (So, do I & neither do I of simple & perfect tenses)',
          'Day-21_ST-4_Eng (Reflexive pronouns of simple & perfect tenses)',
          'Day-22_ST-4_Eng (Possessive pronouns of simple & perfect tenses)',
          'Day-23_ST-4_Eng (Always, never & ever of simple & perfect tenses)',
          'Day-24_ST-4_Eng (Quantifiers of simple & perfect tenses)',
          'Day-25_ST-4_Eng (Degrees of Comparison [Positive & Comparative])',
          'Day-26_ST-4_Eng (Advanced Practice)',
          'Day-27_ST-4_Eng (Future Perfect Review)',
          'Day-28_ST-4_Eng (Final Assessment Material)',
        ],
        'Stage 5': [],
        'Stage 6': [],
        'Stage 7': [],
      },
      'Hindi': {
        'Stage 1': [
          'Day-1_Foundation_Hin (Demo Class & Orientation)',
          'Day-2_Foundation_Hin (+Sta Past BE FORM)',
          'Day-3_Foundation_Hin (- Sta Past BE FORM)',
          'Day-4_Foundation_Hin (+_- Y_N Past BE FORM)',
          'Day-5_Foundation_Hin (+_- W.H Past BE FORM)',
          'Day-6_Foundation_Hin (+Sta Present BE FORM)',
          'Day-7_Foundation_Hin (-Sta Present BE FORM)',
          'Day-8_Foundation_Hin (+Y_N Que Present BE FORM)',
          'Day-9_Foundation_Hin (-Y_N Que Present BE FORM)',
          'Day-10_Foundation_Hin (+W.H Que Present BE FORM)',
          'Day-11_Foundation_Hin (-W.H Que Present BE FORM)',
          'Day-12_Foundation_Hin (+Sta Future BE FORM)',
          'Day-13_Foundation_Hin (-Sta Future BE FORM)',
          'Day-14_Foundation_Hin (+ Y_N Que Future BE FORM)',
          'Day-15_Foundation_Hin (- Y_N Que Future BE FORM)',
          'Day-16_Foundation_Hin (+ W.H Que Future BE FORM)',
          'Day-17_Foundation_Hin (- W.H Que Future BE FORM)',
          'Day-18_Foundation_Hin (+_- Sta There & Here)',
          'Day-19_Foundation_Hin (+_- Y_N Que There & Here)',
          'Day-20_Foundation_Hin (+_- W.H Que There & Here)',
        ],
        'Stage 2': [
          'Day-1_Accuracy_Hin (Demo Class & Orientation)',
          'Day-2_Accuracy_Hin (+ Sta Past Have)',
          'Day-3_Accuracy_Hin (- Sta Past Have)',
          'Day-4_Accuracy_Hin (+ Y_N Past Have)',
          'Day-5_Accuracy_Hin (- Y_N Past Have)',
          'Day-6_Accuracy_Hin (+W.H Past Have)',
          'Day-7_Accuracy_Hin (-W.H Past Have)',
          'Day-8_Accuracy_Hin [(+_-) Sta Present Have]',
          'Day-9_Accuracy_Hin [(+_-) Y_N Present Have]',
          'Day-10_Accuracy_Hin [(+_-) W.H Present Have]',
          'Day-11_Accuracy_Hin [(+_-) Sta Future Have]',
          'Day-12_Accuracy_Hin [(+_-) Y_N Future Have]',
          'Day-13_Accuracy_Hin [(+_-) W.H Future Have]',
          'Day-14_Accuracy_Hin[(+_-) Sta Quantifiers]',
          'Day-15_Accuracy_Hin[(+_-) Y_N Quantifiers]',
          'Day-16_Accuracy_Hin[(+_-) W.H Quantifiers]',
          'Day-17_Accuracy_Hin[Possessive Pronouns]',
          'Day-18_Accuracy_Hin[W.H Words]',
          'Day-19_Accuracy_Hin[Time Prepositions]',
          'Day-20_Accuracy_Hin[Place Prepositions]',
          'Day-21_Accuracy_Hin[Frequency Prepositions',
        ],
        'Stage 3': [
          'Day-1_Progression_Hin (Demo Class & Orientation)',
          'Day-2_Progression_Hin (Action Verbs)',
          'Day-3_Progression_Hin (+Sta Past Simple)',
          'Day-4_Progression_Hin (-Sta Past Simple)',
          'Day-5_Progression_Hin (+Y_N Past Simple)',
          'Day-6_Progression_Hin (-Y_N Past Simple)',
          'Day-7_Progression_Hin (+W.H Past Simple)',
          'Day-8_Progression_Hin (-W.H Past Simple)',
          'Day-9_Progression_Hin (+Sta Present Simple)',
          'Day-10_Progression_Hin (-Sta Present Simple)',
          'Day-11_Progression_Hin (+Y_N Present Simple)',
          'Day-12_Progression_Hin (-Y_N Present Simple)',
          'Day-14_Progression_Hin (-W.H Present Simple)',
          'Day-15_Progression_Hin (+Sta Future Simple)',
          'Day-16_Progression_Hin (-Sta Future Simple)',
          'Day-17_Progression_Hin (+Y_N Future Simple)',
          'Day-18_Progression_Hin (-Y_N Future Simple)',
          'Day-19_Progression_Hin (+W.H Future Simple)',
          'Day-20_Progression_Hin (-W.H Future Simple)',
        ],
        'Stage 4': [
          'Day-1_Clarity_Hin (Demo Class & Orientation)',
          'Day-2_Clarity_Hin (Action Verbs)_.docx',
          'Day-3_Clarity_Hin (+_- Sta Past Con)_ .docx',
          'Day-4_Clarity_Hin (+_- Yes Past Con)_ .docx',
          'Day-5_Clarity_Hin (+_- W.H Past Con)_ .docx',
          'Day-6_Clarity_Hin (+_- Sta Present Con)_ .docx',
          'Day-7_Clarity_Hin (+_- Y_N Que Present Con)_ .docx',
          'Day-8_Clarity_Hin (+_- W.H Que Present Con)_.docx',
          'Day-9_Clarity_Hin (+_- Sta Future Con)_.docx',
          'Day-10_Clarity_Hin (+_- Y_N Que Future Con)_.docx',
          'Day-11_Clarity_Hin (+_- W.H Que Future Con)_.docx',
          'Day-12_Clarity_Hin (+_- Order-1)_.docx',
          'Day-13_Clarity_Hin (+_- Order-2)_.docx',
          'Day-14_Clarity_Hin (+_- Request-1)_.docx',
          'Day-15_Clarity_Hin (+_- Request-2)_.docx',
          'Day-16_Clarity_Hin (+_- Permission-1)_.docx',
          'Day-17_Clarity_Hin (+_- Permission-2)_.docx',
          'Day-18_Clarity_Hin (+ Suggestion-1)_.docx',
          'Day-19_Clarity_Hin (+_- Suggestion-2)_.docx',
        ],
        'Stage 5': [
          'Day-1_Confidence_Hin (Introduction)',
          'Day-2_Confidence_Hin (+_- Sta Past Habit)',
          'Day-3_Confidence_Hin (+_- Yes_No Past Habit)',
          'Day-4_Confidence_Hin (+_- W.H Past Habit)',
          'Day-5_Confidence_Hin (+_- Sta Past Willingness-1)',
          'Day-6_Confidence_Hin (+_- Yes_No Past Willingness-1)',
          'Day-7_Confidence_Hin (+_- W.H Past Willingness-1)',
          'Day-8_Confidence_Hin (+_- Sta Past Ability)',
          'Day-9_Confidence_Hin (+_- Y_N Past Ability)',
          'Day-10_Confidence_Hin (+_- W.H Past Ability)',
          'Day-11_Confidence_Hin (+_- Sta Past Compulsion)',
          'Day-12_Confidence_Hin (+_- Y_N Past Compulsion)',
          'Day-13_Confidence_Hin (+_- W.H Past Compulsion)',
          'Day-14_Confidence_Hin (If In The Past)',
          'Day-15_Confidence_Hin (If In The Present)',
          'Day-16_Confidence_Hin (If In The Future)',
          'Day-17_Confidence_Hin (When In The Past)',
          'Day-18_Confidence_Hin (When In The Present)',
          'Day-19_Confidence_Hin (When In The Future)',
          'Day-20_Confidence_Hin (After In The Past)',
          'Day-22_Confidence_Hin (After In The Future)',
        ],
        'Stage 6': [
          'Day-1_Confidence_Hin (Demo Class & Orientation)',
          'Day-2_Confidence_Hin (+_- Sta Present Willingness-1)',
          'Day-3_Confidence_Hin (Speaking Practice)',
          'Day-4_Confidence_Hin (+_- Yes_No Present Willingness-1)',
          'Day-5_Confidence_Hin (Speaking Practice)',
          'Day-6_Confidence_Hin (+_- W.H Present Willingness-1)',
          'Day-7_Confidence_Hin (Speaking Practice)',
          'Day-8_Confidence_Hin (+_- Sta Present Perm Ability)',
          'Day-9_Confidence_Hin (+_- Y_N Present Perm Ability)',
          'Day-10_Confidence_Hin (+_- W.H Present Perm Ability)',
          'Day-11_Confidence_Hin (Speaking Practice)',
          'Day-12_Confidence_Hin (+_- Sta Present Temp Ability)',
          'Day-13_Confidence_Hin (+_- Y_N & W.H Present Temp Ability)',
          'Day-14_Confidence_Hin (Speaking Practice)',
          'Day-15_Confidence_Hin (+_- Sta Present Compulsion)',
          'Day-16_Confidence_Hin (+_- Y_N Present Compulsion)',
          'Day-17_Confidence_Hin (Speaking Practice)',
          'Day-18_Confidence_Hin (Before in the Past)',
          'Day-19_Confidence_Hin (Before in the Present)',
          'Day-20_Confidence_Hin (Before in the Future)',
          'Day-21_Confidence_Hin (Speaking Practice)',
          'Day-22_Confidence_Hin (Speaking Practice)',
        ],
        'Stage 7': [],
      },
    };

    final langKey = isHindi ? 'Hindi' : 'English';
    final List<String> assignedFiles =
        allNotes[langKey]?[assignedStageKey] ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isDesktop = width >= 1000;
        final bool isTablet = width >= 650 && width < 1000;

        return Scaffold(
          backgroundColor: background,
          appBar: _buildAppBar(
            context,
            '$assignedStageKey ($langKey)',
            assignedFiles.length,
            isDesktop,
          ),
          body: assignedFiles.isEmpty
              ? _buildEmptyState(assignedStageKey)
              : _buildMaterialsBody(
                  context,
                  assignedFiles,
                  stageFolder,
                  assignedStageKey,
                  isDesktop,
                  isTablet,
                ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    String stage,
    int totalMaterials,
    bool isDesktop,
  ) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: navy,
      toolbarHeight: isDesktop ? 72 : 64,
      automaticallyImplyLeading: false,
      title: Padding(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 18 : 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: teal,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: teal.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: Colors.white,
                size: 23,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Learning Materials',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: isDesktop ? 17 : 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$stage • $totalMaterials lessons',
                    style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialsBody(
    BuildContext context,
    List<String> files,
    String stageFolder,
    String stage,
    bool isDesktop,
    bool isTablet,
  ) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [background, backgroundDark],
        ),
      ),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isDesktop ? 40 : 18,
                isDesktop ? 28 : 20,
                isDesktop ? 40 : 18,
                18,
              ),
              child: _buildWelcomeHeader(stage, files.length, isDesktop),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              isDesktop ? 40 : 18,
              0,
              isDesktop ? 40 : 18,
              30,
            ),
            sliver: isDesktop || isTablet
                ? _buildGrid(context, files, stageFolder, isDesktop)
                : _buildMobileList(context, files, stageFolder),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeHeader(String stage, int count, bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 25 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [navy, blue],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your teaching library',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: isDesktop ? 22 : 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Open a lesson to view the PDF and start teaching.',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    List<String> files,
    String stageFolder,
    bool isDesktop,
  ) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        return _buildMaterialCard(
          context,
          files[index],
          index,
          stageFolder,
          isDesktop,
        );
      }, childCount: files.length),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isDesktop ? 3 : 2,
        crossAxisSpacing: isDesktop ? 18 : 14,
        mainAxisSpacing: isDesktop ? 18 : 14,
        childAspectRatio: isDesktop ? 2.55 : 2.0,
      ),
    );
  }

  Widget _buildMobileList(
    BuildContext context,
    List<String> files,
    String stageFolder,
  ) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildMaterialCard(
            context,
            files[index],
            index,
            stageFolder,
            false,
          ),
        );
      }, childCount: files.length),
    );
  }

  Widget _buildMaterialCard(
    BuildContext context,
    String fileName,
    int index,
    String stageFolder,
    bool isDesktop,
  ) {
    final bool isPractice =
        fileName.contains('🔴') || fileName.toLowerCase().contains('practice');
    final bool isDemo =
        fileName.toLowerCase().contains('demo') ||
        fileName.toLowerCase().contains('orientation');

    final String cleanTitle = fileName.replaceAll('🔴', '').trim();
    final String dayNumber = _extractDayNumber(fileName);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: () {
          if (isDemo) {
            Get.dialog(
              Dialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_lesson_rounded,
                        color: navy,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Demo & Orientation Class',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: deepNavy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Day 1 is a live interactive session conducted by the trainer. No PDF download is required.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: Get.back,
                        style: ElevatedButton.styleFrom(backgroundColor: navy),
                        child: const Text(
                          'Got it',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          } else {
            Get.to(
              () =>
                  PdfViewerScreen(fileName: fileName, stageFolder: stageFolder),
            );
          }
        },
        child: Ink(
          decoration: BoxDecoration(
            color: white,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: isPractice
                  ? yellow.withValues(alpha: 0.45)
                  : navy.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: navy.withValues(alpha: 0.07),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: isDesktop ? 48 : 46,
                  height: isDesktop ? 48 : 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isPractice
                          ? [yellow, const Color(0xFFF1C93B)]
                          : [navy, blue],
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'DAY',
                        style: GoogleFonts.poppins(
                          color: isPractice
                              ? deepNavy
                              : Colors.white.withValues(alpha: 0.68),
                          fontSize: 7,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        dayNumber,
                        style: GoogleFonts.poppins(
                          color: isPractice ? deepNavy : Colors.white,
                          fontSize: 16,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        cleanTitle,
                        maxLines: isDesktop ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: deepNavy,
                          fontSize: isDesktop ? 11.5 : 11,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String stage) {
    return Center(
      child: Text(
        'No materials found for $stage',
        style: GoogleFonts.poppins(color: deepNavy, fontSize: 16),
      ),
    );
  }

  String _extractDayNumber(String value) {
    final RegExp regex = RegExp(r'Day-(\d+)');
    final Match? match = regex.firstMatch(value);
    if (match != null) {
      return match.group(1) ?? '1';
    }
    return '1';
  }
}
