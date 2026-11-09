import 'package:flutter/material.dart';

class FilmModel {
  final String id;          // AS, BB, CC,...
  final String fullName;    // ASTIA 100F
  final String shortLabel;  // ASTIA
  final String subLabel;    // 100F
  final String lutPath;
  final String imagePath;
  final Color themeColor;
  final String iso;

  const FilmModel({
    required this.id,
    required this.fullName,
    required this.shortLabel,
    required this.subLabel,
    required this.lutPath,
    required this.imagePath,
    required this.themeColor,
    required this.iso,
  });

  static const List<FilmModel> fujiCatalog = [
    FilmModel(
      id: 'AS',
      fullName: 'ASTIA 100F',
      shortLabel: 'ASTIA',
      subLabel: '100F',
      lutPath: 'assets/luts/astia_sRGB.cube',
      imagePath: 'assets/images/AS.png',
      themeColor: Color(0xFFC94F7C),
      iso: '100',
    ),
    FilmModel(
      id: 'BB',
      fullName: 'BLEACH BYPASS',
      shortLabel: 'BLEACH',
      subLabel: 'BYPASS',
      lutPath: 'assets/luts/bleach bypass_sRGB.cube',
      imagePath: 'assets/images/BB.png',
      themeColor: Color(0xFF7E8489),
      iso: '400',
    ),
    FilmModel(
      id: 'CC',
      fullName: 'CLASSIC CHROME',
      shortLabel: 'CLASSIC',
      subLabel: '64',
      lutPath: 'assets/luts/classic chrome_sRGB.cube',
      imagePath: 'assets/images/CC.png',
      themeColor: Color(0xFF3F7078),
      iso: '200',
    ),
    FilmModel(
      id: 'CN',
      fullName: 'SUPERIA C-NEG',
      shortLabel: 'C-NEG',
      subLabel: '160',
      lutPath: 'assets/luts/classic neg_sRGB.cube',
      imagePath: 'assets/images/CN.png',
      themeColor: Color(0xFF1E824C),
      iso: '160',
    ),
    FilmModel(
      id: 'ET',
      fullName: 'ETERNA 250D',
      shortLabel: 'ETERNA',
      subLabel: '250D',
      lutPath: 'assets/luts/eterna_sRGB.cube',
      imagePath: 'assets/images/ET.png',
      themeColor: Color(0xFF8A6543),
      iso: '250',
    ),
    FilmModel(
      id: 'NN',
      fullName: 'NOSTALGIC NEG',
      shortLabel: 'NOSTAL',
      subLabel: 'NEG',
      lutPath: 'assets/luts/nostalgic neg_sRGB.cube',
      imagePath: 'assets/images/NN.png',
      themeColor: Color(0xFFB57022),
      iso: '400',
    ),
    FilmModel(
      id: 'PH',
      fullName: 'PRO NEG HI',
      shortLabel: 'PRO HI',
      subLabel: '400',
      lutPath: 'assets/luts/pro neg hi_sRGB.cube',
      imagePath: 'assets/images/PH.png',
      themeColor: Color(0xFFA53A2A),
      iso: '400',
    ),
    FilmModel(
      id: 'PS',
      fullName: 'PRO NEG STD',
      shortLabel: 'PRO STD',
      subLabel: '160',
      lutPath: 'assets/luts/pro neg std_sRGB.cube',
      imagePath: 'assets/images/PS.png',
      themeColor: Color(0xFF2E7D73),
      iso: '160',
    ),
    FilmModel(
      id: 'PV',
      fullName: 'PROVIA 100F',
      shortLabel: 'PROVIA',
      subLabel: '100F',
      lutPath: 'assets/luts/provia_sRGB.cube',
      imagePath: 'assets/images/PV.png',
      themeColor: Color(0xFF2860B8),
      iso: '100',
    ),
    FilmModel(
      id: 'RA',
      fullName: 'REALA ACE',
      shortLabel: 'ACE',
      subLabel: '100',
      lutPath: 'assets/luts/reala ace_sRGB.cube',
      imagePath: 'assets/images/RA.png',
      themeColor: Color(0xFF008374),
      iso: '100',
    ),
    FilmModel(
      id: 'VL',
      fullName: 'VELVIA 50',
      shortLabel: 'VELVIA',
      subLabel: '50',
      lutPath: 'assets/luts/velvia_sRGB.cube',
      imagePath: 'assets/images/VL.png',
      themeColor: Color(0xFF8E1B77),
      iso: '50',
    ),
  ];
}