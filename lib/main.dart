import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:catalogo_digital_app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://aesmdplpcxybjzmwnjbw.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFlc21kcGxwY3h5Ymp6bXduamJ3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU5MzQwNDIsImV4cCI6MjA5MTUxMDA0Mn0.Ixxuql-Mrem6zdOSLoWyWQ2YPithJCK3MWCwhF72_fQ',
  );

  runApp(const MyApp());
}
