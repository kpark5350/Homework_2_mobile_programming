import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

final auth = FirebaseAuth.instance;
final db = FirebaseFirestore.instance;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Message Board',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const SplashPage(),
    );
  }
}

// Splash screen
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    startApp();
  }

  Future<void> startApp() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.message, size: 70, color: Colors.blue),
            SizedBox(height: 15),
            Text('Message Board', style: TextStyle(fontSize: 26)),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// Login status
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Authentication error')),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const BoardPage();
        }
        return const LoginPage();
      },
    );
  }
}

// Login and register
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final first = TextEditingController();
  final last = TextEditingController();

  bool register = false;
  bool loading = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    first.dispose();
    last.dispose();
    super.dispose();
  }

  void showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      showError('Please enter email and password');
      return;
    }

    if (register && (first.text.trim().isEmpty || last.text.trim().isEmpty)) {
      showError('Please enter your name');
      return;
    }

    setState(() => loading = true);

    try {
      if (register) {
        final result = await auth.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );

        await db.collection('users').doc(result.user!.uid).set({
          'uid': result.user!.uid,
          'firstName': first.text.trim(),
          'lastName': last.text.trim(),
          'role': 'student',
          'registrationDateTime': FieldValue.serverTimestamp(),
        });
      } else {
        await auth.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      showError(e.message ?? 'Login failed');
    } catch (e) {
      showError('Error: $e');
    }

    if (mounted) setState(() => loading = false);
  }

  Widget input(
    TextEditingController controller,
    String label, {
    bool hidden = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: hidden,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Message Board')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle, size: 70, color: Colors.blue),
              const SizedBox(height: 15),
              Text(
                register ? 'Register' : 'Login',
                style: const TextStyle(fontSize: 25),
              ),
              const SizedBox(height: 20),

              if (register) ...[
                input(first, 'First Name'),
                input(last, 'Last Name'),
              ],

              input(email, 'Email'),
              input(password, 'Password', hidden: true),

              ElevatedButton(
                onPressed: loading ? null : submit,
                child: Text(register ? 'Register' : 'Login'),
              ),

              if (loading) const CircularProgressIndicator(),

              TextButton(
                onPressed: loading
                    ? null
                    : () => setState(() => register = !register),
                child: Text(
                  register
                      ? 'Already have an account? Login'
                      : 'Create an account',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Message board
class BoardPage extends StatefulWidget {
  const BoardPage({super.key});

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  final message = TextEditingController();
  bool sending = false;

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  void notice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> addMessage() async {
    final text = message.text.trim();

    if (text.isEmpty || text.length > 500) {
      notice('Message must be 1-500 characters');
      return;
    }

    if (sending) return;
    setState(() => sending = true);

    try {
      final uid = auth.currentUser!.uid;
      final user = await db.collection('users').doc(uid).get();
      final data = user.data();

      if (data == null) {
        notice('User profile not found');
        return;
      }

      final name = '${data['firstName']} ${data['lastName']}';

      await db.collection('messages').add({
        'text': text,
        'authorUid': uid,
        'authorName': name,
        'createdAt': FieldValue.serverTimestamp(),
        'editedAt': null,
      });

      message.clear();
    } catch (e) {
      notice('Error: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> editMessage(String id, String oldText) async {
    String newText = oldText;

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextFormField(
          initialValue: oldText,
          maxLines: 3,
          maxLength: 500,
          onChanged: (value) => newText = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (save != true) return;

    newText = newText.trim();

    if (newText.isEmpty || newText.length > 500) {
      notice('Invalid message');
      return;
    }

    try {
      await db.collection('messages').doc(id).update({
        'text': newText,
        'editedAt': FieldValue.serverTimestamp(),
      });
      notice('Message updated');
    } catch (e) {
      notice('Error: $e');
    }
  }

  Future<void> deleteMessage(String id) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (yes != true) return;

    try {
      await db.collection('messages').doc(id).delete();
      notice('Message deleted');
    } catch (e) {
      notice('Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Board'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await auth.signOut();
              } catch (e) {
                notice('Logout failed: $e');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: message,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Write a message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sending ? null : addMessage,
                ),
              ],
            ),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return const Center(child: Text('No messages yet'));
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final mine = data['authorUid'] == uid;

                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        title: Text(data['authorName'] ?? 'Unknown'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            Text(data['text'] ?? ''),
                            if (data['editedAt'] != null)
                              const Text(
                                'Edited',
                                style: TextStyle(fontSize: 11),
                              ),
                          ],
                        ),
                        trailing: mine
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    editMessage(doc.id, data['text']);
                                  } else {
                                    deleteMessage(doc.id);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
