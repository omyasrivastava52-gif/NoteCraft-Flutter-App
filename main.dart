import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

class Note {
  final String id;
  String title;
  String content;
  String category;
  final String tag;
  final String userId;
  bool isPinned;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.tag,
    required this.userId,
    this.isPinned = false,
  });

  factory Note.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Note(
      id: doc.id,
      title: data?['title'] as String? ?? "",
      content: data?['content'] as String? ?? "",
      category: data?['category'] as String? ?? "NEW",
      tag: data?['tag'] as String? ?? "Draft",
      userId: data?['userId'] as String? ?? "",
      isPinned: data?['isPinned'] as bool? ?? false,
    );
  }

  Map<String, Object?> toCreateMap() {
    return {
      'title': title,
      'content': content,
      'category': category,
      'tag': tag,
      'userId': userId,
      'isPinned': isPinned,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, Object?> toUpdateMap() {
    return {
      'title': title,
      'content': content,
      'category': category,
      'tag': tag,
      'userId': userId,
      'isPinned': isPinned,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  bool _isLoggedIn = false;
  int _selectedIndex = 0;
  User? _currentUser;
  List<Note> notes = [];
  dynamic _notesSubscription; // Holds the real-time pipeline reference cleanly

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _currentUser = currentUser;
      _isLoggedIn = true;
      _initNotesStream(currentUser.uid);
    }
  }

  @override
  void dispose() {
    _notesSubscription?.cancel();
    super.dispose();
  }

  void _showFirestoreError(String message) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // Realtime pipeline listener shifts gracefully into global state initialization
  void _initNotesStream(String uid) {
    _notesSubscription?.cancel();
    _notesSubscription = FirebaseFirestore.instance
        .collection('notes')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (querySnapshot) {
            final freshNotes = querySnapshot.docs
                .map((doc) => Note.fromDocument(doc))
                .toList();

            if (mounted) {
              setState(() {
                notes = freshNotes;
              });
            }
          },
          onError: (error) {
            _showFirestoreError('Unable to sync live notes from Firestore.');
          },
        );
  }

  Future<Note?> saveNoteToFirestore(Note note) async {
    final uid = _currentUser?.uid;
    if (uid == null) {
      _showFirestoreError('You must be logged in to save notes.');
      return null;
    }

    final notesCollection = FirebaseFirestore.instance.collection('notes');
    try {
      if (note.id.isEmpty) {
        final docRef = await notesCollection.add(note.toCreateMap());
        final snapshot = await docRef.get();
        return Note.fromDocument(snapshot);
      } else {
        final docRef = notesCollection.doc(note.id);
        await docRef.update(note.toUpdateMap());
        final snapshot = await docRef.get();
        return Note.fromDocument(snapshot);
      }
    } catch (e) {
      _showFirestoreError('Unable to save note to Firestore.');
      return null;
    }
  }

  Future<void> deleteNote(Note note) async {
    if (note.id.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('notes')
          .doc(note.id)
          .delete();
    } catch (e) {
      _showFirestoreError('Unable to delete note.');
    }
  }

  void _handleLogin() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    setState(() {
      _isLoggedIn = true;
      _currentUser = currentUser;
    });
    _initNotesStream(currentUser.uid);
  }

  Future<void> handleLogout() async {
    _notesSubscription?.cancel();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    setState(() {
      _isLoggedIn = false;
      _selectedIndex = 0;
      _currentUser = null;
      notes = [];
    });
  }

  void _onTabSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _handleNoteSaved(Note note) async {
    await saveNoteToFirestore(note);
  }

  void createNote() {
    if (_currentUser == null) return;

    final newNote = Note(
      id: '',
      title: 'New note',
      content: 'Start typing to capture your next idea...',
      category: 'NEW',
      tag: 'Draft',
      userId: _currentUser!.uid,
      isPinned: false,
    );

    navigatorKey.currentState
        ?.push<Note>(
          MaterialPageRoute(
            builder: (context) => NoteEditorScreen(note: newNote),
          ),
        )
        .then((updatedNote) async {
          if (updatedNote != null && mounted) {
            _handleNoteSaved(updatedNote);
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    const scaffoldBg = Color(0xFF0B1420);
    const surfaceBg = Color(0xFF121E32);

    const colorScheme = ColorScheme.dark(
      surface: surfaceBg,
      onSurface: Colors.white,
      primary: Color(0xFF1E88E5),
      onPrimary: Colors.white,
      secondary: Color(0xFFF5A623),
      onSecondary: Color(0xFF102542),
      error: Color(0xFFEF5350),
    );

    final theme = ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      canvasColor: surfaceBg,
      cardColor: const Color(0xFF14233A),
      textTheme: ThemeData.dark(
        useMaterial3: true,
      ).textTheme.apply(bodyColor: Colors.white70, displayColor: Colors.white),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF0F1A2E),
        labelStyle: TextStyle(color: Color(0xFF8AB4F8)),
        hintStyle: TextStyle(color: Colors.white38),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide.none,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondary,
          foregroundColor: colorScheme.onSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF0F1A2E),
        selectedItemColor: Color(0xFFF5A623),
        unselectedItemColor: Colors.white54,
        showUnselectedLabels: true,
      ),
    );

    final pages = <Widget>[
      AllNotesScreen(
        notes: notes, 
        onNoteSaved: _handleNoteSaved,
        onDeleteNote: deleteNote,
        onAddNote: createNote,
      ),
      PinnedNotesScreen(notes: notes, onNoteSaved: _handleNoteSaved),
      CategoriesScreen(notes: notes),
      ProfileScreen(onLogout: handleLogout),
    ];

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'NoteCraft Notes',
      theme: theme,
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _isLoggedIn
            ? Scaffold(
                key: const ValueKey('main_app'),
                body: SafeArea(
                  child: IndexedStack(index: _selectedIndex, children: pages),
                ),
                floatingActionButton: _selectedIndex == 0
                    ? FloatingActionButton.extended(
                        onPressed: createNote,
                        icon: const Icon(Icons.add),
                        label: const Text('New Note'),
                      )
                    : null,
                floatingActionButtonLocation:
                    FloatingActionButtonLocation.endFloat,
                bottomNavigationBar: BottomNavigationBar(
                  currentIndex: _selectedIndex,
                  onTap: _onTabSelected,
                  type: BottomNavigationBarType.fixed,
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.sticky_note_2_outlined),
                      label: 'All Notes',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.push_pin_outlined),
                      label: 'Pinned',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.folder_open_outlined),
                      label: 'Categories',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline),
                      label: 'Profile',
                    ),
                  ],
                ),
              )
            : LoginScreen(onLogin: _handleLogin),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  final VoidCallback onLogin;
  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _showPassword = false;
  bool _isSignUpMode = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        (_isSignUpMode && username.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isSignUpMode) {
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        await userCredential.user?.updateDisplayName(username);
        await userCredential.user?.reload();
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      if (!mounted) return;
      widget.onLogin();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Authentication failed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An unexpected error occurred.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF081621), Color(0xFF0B1B2C)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                const Text(
                  'NoteCraft',
                  style: TextStyle(
                    color: Color(0xFFF5A623),
                    fontSize: 42,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Organize your ideas with clarity, focus and style.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 17,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 44),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  color: const Color(0xFF12213A),
                  elevation: 20,
                  child: Padding(
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isSignUpMode ? 'Create Account' : 'Welcome back',
                          style: const TextStyle(
                            color: Color(0xFFEF6C00),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isSignUpMode
                              ? 'Sign up to start organizing your dashboard.'
                              : 'Login to continue to your note dashboard.',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_isSignUpMode) ...[
                          TextField(
                            controller: _usernameController,
                            keyboardType: TextInputType.name,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              hintText: 'Choose your unique username',
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            hintText: 'hello@youremail.com',
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: '••••••••',
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.white54,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showPassword = !_showPassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleSubmit,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isLoading)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              else ...[
                                Text(
                                  _isSignUpMode ? 'Register Account' : 'Log In',
                                ),
                                const SizedBox(width: 10),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _isSignUpMode = !_isSignUpMode;
                              });
                            },
                            child: Text(
                              _isSignUpMode
                                  ? 'Already have an account? Log In'
                                  : 'Don\'t have an account? Sign Up',
                              style: const TextStyle(color: Color(0xFFF5A623)),
                            ),
                          ),
                        ),
                        
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'Secure, simple and instantly familiar.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



class AllNotesScreen extends StatelessWidget {
  final List<Note> notes;
  final ValueChanged<Note> onNoteSaved;
  final ValueChanged<Note> onDeleteNote;
  final VoidCallback onAddNote;

  const AllNotesScreen({
    super.key,
    required this.notes,
    required this.onNoteSaved,
    required this.onDeleteNote,
    required this.onAddNote,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: _SectionHeader(
                  title: 'All Notes',
                  subtitle:
                      'A curated view of your latest drafts and insights.',
                ),
              ),
              ElevatedButton.icon(
                onPressed: onAddNote,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5A623),
                  foregroundColor: const Color(0xFF102542),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: notes.isEmpty
                ? const Center(
                    child: Text(
                      'No notes found yet. Create one to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : GridView.builder(
                    itemCount: notes.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.78,
                        ),
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () async {
                            final updatedNote = await navigatorKey.currentState
                                ?.push<Note>(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        NoteEditorScreen(note: note),
                                  ),
                                );
                            if (updatedNote != null) {
                              onNoteSaved(updatedNote);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: index.isEven
                                  ? const Color(0xFF142741)
                                  : const Color(0xFF12203A),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 14,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0x2EEF6C00),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Text(
                                          note.category,
                                          style: const TextStyle(
                                            color: Color(0xFFF5A623),
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        constraints: const BoxConstraints(),
                                        padding: EdgeInsets.zero,
                                        icon: Icon(
                                          note.isPinned
                                              ? Icons.star
                                              : Icons.star_border,
                                          color: note.isPinned
                                              ? const Color(0xFFF5A623)
                                              : Colors.white54,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          note.isPinned = !note.isPinned;
                                          onNoteSaved(note);
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    note.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Expanded(
                                    child: Text(
                                      note.content,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        height: 1.5,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 5,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        note.tag,
                                        style: const TextStyle(
                                          color: Colors.white38,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            onPressed: () async {
                                              final confirmed =
                                                  await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) {
                                                      return AlertDialog(
                                                        title: const Text(
                                                          'Delete note',
                                                        ),
                                                        content: const Text(
                                                          'Are you sure you want to delete this note?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  context,
                                                                ).pop(false),
                                                            child: const Text(
                                                              'Cancel',
                                                            ),
                                                          ),
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(
                                                                  context,
                                                                ).pop(true),
                                                            child: const Text(
                                                              'Delete',
                                                            ),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  );
                                              if (confirmed == true) {
                                                onDeleteNote(note);
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.white38,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.more_horiz,
                                            color: Colors.white38,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class NoteEditorScreen extends StatefulWidget {
  final Note note;
  const NoteEditorScreen({super.key, required this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late String _selectedCategory;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _contentController = TextEditingController(text: widget.note.content);
    _selectedCategory =
        ['Design', 'Projects', 'Ideas', 'NEW'].contains(widget.note.category)
        ? widget.note.category
        : 'NEW';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveAndClose() async {
    if (_isSaving) return;

    final title = _titleController.text.trim().isEmpty
        ? 'Untitled note'
        : _titleController.text.trim();
    final content = _contentController.text.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.note.userId;

    if (uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to save notes.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final notesCollection = FirebaseFirestore.instance.collection('notes');

      if (widget.note.id.isEmpty) {
        final docRef = notesCollection.doc();
        final newNote = Note(
          id: docRef.id,
          title: title,
          content: content,
          category: _selectedCategory,
          tag: widget.note.tag,
          userId: uid,
          isPinned: widget.note.isPinned,
        );
        await docRef.set(newNote.toCreateMap());
        if (!mounted) return;
        Navigator.of(context).pop(newNote);
      } else {
        final updatedNote = Note(
          id: widget.note.id,
          title: title,
          content: content,
          category: _selectedCategory,
          tag: widget.note.tag,
          userId: uid,
          isPinned: widget.note.isPinned,
        );
        await notesCollection
            .doc(widget.note.id)
            .update(updatedNote.toUpdateMap());
        if (!mounted) return;
        Navigator.of(context).pop(updatedNote);
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to save note.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Note'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveAndClose,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isSaving ? null : _saveAndClose,
        child: _isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.save),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Assign Category:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                DropdownButton<String>(
                  value: _selectedCategory,
                  dropdownColor: const Color(0xFF12213A),
                  style: const TextStyle(
                    color: Color(0xFFF5A623),
                    fontWeight: FontWeight.bold,
                  ),
                  onChanged: _isSaving
                      ? null
                      : (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedCategory = newValue;
                            });
                          }
                        },
                  items: <String>['Design', 'Projects', 'Ideas', 'NEW']
                      .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      })
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              enabled: !_isSaving,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'What will this note be about?',
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: TextField(
                controller: _contentController,
                enabled: !_isSaving,
                maxLines: null,
                expands: true,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
                decoration: const InputDecoration(
                  labelText: 'Body',
                  hintText: 'Capture your thoughts here...',
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PinnedNotesScreen extends StatelessWidget {
  final List<Note> notes;
  final ValueChanged<Note> onNoteSaved;

  const PinnedNotesScreen({
    super.key, 
    required this.notes, 
    required this.onNoteSaved,
  });

  @override
  Widget build(BuildContext context) {
    final pinnedNotes = notes.where((note) => note.isPinned).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Pinned Notes',
            subtitle: 'High-priority reminders and journal items.',
          ),
          const SizedBox(height: 18),
          Expanded(
            child: pinnedNotes.isEmpty
                ? const Center(
                    child: Text(
                      'No pinned notes yet.\nTap the star icon on a note card to pin it here!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.4),
                    ),
                  )
                : ListView.separated(
                    itemCount: pinnedNotes.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final note = pinnedNotes[index];
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A304F),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: const Color(0xFF27466B)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    note.title,
                                    style: const TextStyle(
                                      color: Color(0xFFFFB300),
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.star, color: Color(0xFFEF6C00)),
                                  onPressed: () {
                                    note.isPinned = false;
                                    onNoteSaved(note); 
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              note.content,
                              style: const TextStyle(color: Colors.white70, height: 1.5),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                _StatusChip(label: note.category, color: const Color(0xFF8AB4F8)),
                                const SizedBox(width: 10),
                                _StatusChip(label: note.tag, color: const Color(0xFF80CBC4)),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CategoriesScreen extends StatelessWidget {
  final List<Note> notes;

  const CategoriesScreen({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    final Map<String, int> categoryCounts = {};
    for (var note in notes) {
      final cat = note.category.isEmpty ? 'Uncategorized' : note.category;
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
    }

    final trackedCategories = [
      {'title': 'Design', 'icon': Icons.palette_outlined, 'color': const Color(0xFF8AB4F8)},
      {'title': 'Projects', 'icon': Icons.lightbulb_outline, 'color': const Color(0xFF80CBC4)},
      {'title': 'Ideas', 'icon': Icons.bookmark_outline, 'color': const Color(0xFFB39DDB)},
      {'title': 'NEW', 'icon': Icons.fiber_new_outlined, 'color': const Color(0xFFFFC107)},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Categories',
            subtitle: 'Folders and labels for a clean note structure.',
          ),
          const SizedBox(height: 18),
          Expanded(
            child: GridView.builder(
              itemCount: trackedCategories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.05,
              ),
              itemBuilder: (context, index) {
                final catData = trackedCategories[index];
                final String title = catData['title'] as String;
                final int liveCount = categoryCounts[title] ?? 0;

                return _CategoryCard(
                  title: title,
                  count: liveCount,
                  icon: catData['icon'] as IconData,
                  color: catData['color'] as Color,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  final VoidCallback onLogout;
  const ProfileScreen({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: 'Profile',
            subtitle: 'Manage account access, preferences, and appearance.',
          ),
          const SizedBox(height: 22),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Card(
                elevation: 14,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF102741), Color(0xFF12203A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFFF5A623), Color(0xFFEF6C00)],
                              ),
                            ),
                            child: const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 38,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName != null &&
                                          user!.displayName!.isNotEmpty
                                      ? user.displayName!
                                      : 'Crafterman User',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user?.email ?? 'anonymous@noteapp.com',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Colors.white12, thickness: 1),
                      const SizedBox(height: 20),
                      const _ProfileTile(
                        title: 'Workspace',
                        value: 'Idea Lab',
                        icon: Icons.workspace_premium_outlined,
                      ),
                      const _ProfileTile(
                        title: 'Theme',
                        value: 'Slate Blue',
                        icon: Icons.palette_outlined,
                      ),
                      const _ProfileTile(
                        title: 'Notifications',
                        value: 'Enabled',
                        icon: Icons.notifications_active_outlined,
                      ),
                      const _ProfileTile(
                        title: 'Security',
                        value: '2FA Active',
                        icon: Icons.shield_outlined,
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white12, thickness: 1),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onLogout,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Log Out'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF5350),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFFB300),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(46),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;

  const _CategoryCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF102636),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withAlpha(56)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(46),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '$count notes',
            style: TextStyle(color: Colors.white.withAlpha(179)),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _ProfileTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF1A2D4B),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF8AB4F8), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white60)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white24),
        ],
      ),
    );
  }
}
