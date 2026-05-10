import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'profile_settings_page.dart';
import 'api_constants.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter/services.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'shopping_page.dart';
import 'api_service.dart';
import 'laptop_details_page.dart';

String sanitizeUtf16(String input) {
  if (input.isEmpty) return input;

  final buffer = StringBuffer();
  int i = 0;

  while (i < input.length) {
    final codeUnit = input.codeUnitAt(i);

    // High surrogate (0xD800–0xDBFF)
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
      if (i + 1 < input.length) {
        final next = input.codeUnitAt(i + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          // Valid pair
          buffer.writeCharCode(codeUnit);
          buffer.writeCharCode(next);
          i += 2;
          continue;
        }
      }
      // Invalid high surrogate → replace
      buffer.write('�'); // U+FFFD
      i++;
    }
    // Low surrogate without high → invalid
    else if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
      buffer.write('�');
      i++;
    }
    // Valid ASCII or other
    else if (codeUnit < 0xD800 || (codeUnit > 0xDFFF && codeUnit <= 0x10FFFF)) {
      buffer.writeCharCode(codeUnit);
      i++;
    }
    // Invalid code unit
    else {
      buffer.write('�');
      i++;
    }
  }

  return buffer.toString();
}

class SafeMarkdown extends StatelessWidget {
  final String data;
  final void Function(String text, String? href, String title)?
  onTapLink; // new

  const SafeMarkdown({
    super.key,
    required this.data,
    this.onTapLink,
  }); // updated

  @override
  Widget build(BuildContext context) {
    final clean = sanitizeUtf16(data);
    return MarkdownBody(
      data: clean,
      onTapLink: onTapLink, // forward callback so links are tappable
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(color: Color(0xFF37474F), fontSize: 16, height: 1.4),
        strong: const TextStyle(fontWeight: FontWeight.bold),
        code: const TextStyle(
          fontFamily: 'monospace',
          backgroundColor: Color(0xFFE0E0E0),
          fontSize: 14,
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
        blockquoteDecoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFF4DD0E1), width: 3)),
        ),
      ),
    );
  }
}

class ChatbotPage extends StatefulWidget {
  final String userName;
  final String? userAvatar;
  final String userId;
  final VoidCallback? onUserUpdate;
  final String? selectedModel;

  const ChatbotPage({
    super.key,
    required this.userName,
    this.userAvatar,
    required this.userId,
    this.onUserUpdate,
    this.selectedModel,
  });

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  late String _userName;
  String? _userAvatar;
  final TextEditingController _messageController = TextEditingController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _chatBoundaryKey = GlobalKey();
  final List<dynamic> _messages = [];
  bool _conversationStarted = false;
  late ScrollController _scrollController;
  String? _conversationId;
  String? _conversationTitle;
  bool _isLoading = false;

  // new: track whether the user is near the bottom and whether to show the jump button
  bool _isUserNearBottom = true;
  bool _showScrollToBottom = false;
  final double _bottomThreshold = 100.0;
  late VoidCallback _scrollListener;

  final TextEditingController _sidebarSearchController =
      TextEditingController();

  // Sidebar conversation list
  List<Map<String, dynamic>> _conversationList = [];
  bool _isLoadingList = false;

  @override
  void initState() {
    super.initState();
    _userName = widget.userName;
    _userAvatar = widget.userAvatar;
    _scrollController = ScrollController();
    _loadConversationList();

    // add scroll listener to detect user's scroll position
    _scrollListener = () {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final isNear = (pos.maxScrollExtent - pos.pixels) <= _bottomThreshold;
      if (isNear != _isUserNearBottom) {
        setState(() {
          _isUserNearBottom = isNear;
          if (isNear) _showScrollToBottom = false;
        });
      }
    };
    _scrollController.addListener(_scrollListener);

    // Auto-send model explanation if provided
    /*
    if (widget.selectedModel != null && widget.selectedModel!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final prompt = "Explain the model ${widget.selectedModel} in detail with specification, pros and cons. Don't recommend any laptops. Please access the database for the specifications.";
        _sendMessage(prompt);
      });
    }*/
  }

  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    final currentScroll = position.pixels;

    final bool isNearBottom = (maxScroll - currentScroll) <= _bottomThreshold;
    final bool shouldScroll = force || isNearBottom;

    if (shouldScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          // once we force scroll, hide the jump button
          if (force && mounted) {
            setState(() {
              _showScrollToBottom = false;
              _isUserNearBottom = true;
            });
          }
        }
      });
    }
  }

  void _copyMessage(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied!'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFE8E4E1),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Profile Settings'),
              onTap: () async {
                Navigator.pop(context);
                final updatedUser = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ProfileSettingsPage(),
                  ),
                );

                if (updatedUser != null && mounted) {
                  setState(() {
                    _userName = updatedUser['username'] ?? _userName;
                    final photoUrl = updatedUser['photoUrl'];
                    if (photoUrl != null && photoUrl.toString().isNotEmpty) {
                      _userAvatar = "${ApiConstants.baseUrl}$photoUrl";
                    } else {
                      _userAvatar = null;
                    }
                  });
                  widget.onUserUpdate?.call();
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove("jwt_token");
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (route) => false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> getUserIdFromToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null && !JwtDecoder.isExpired(token)) {
      final decoded = JwtDecoder.decode(token);
      return decoded['id'];
    }
    return null;
  }

  Future<void> _saveConversationToDatabase(List<dynamic> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final userId = await getUserIdFromToken();

      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/conversation/save'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          "Content-Type": "application/json",
          "ngrok-skip-browser-warning": "true",
        },
        body: jsonEncode({
          'userId': userId,
          'conversationId': _conversationId,
          'messages': messages,
        }),
      );

      if (response.statusCode != 201) {
        debugPrint('Failed to save conversation: ${response.body}');
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _conversationId = data['_id'] ?? _conversationId;
        });
      }
    } catch (e) {
      debugPrint('Error saving conversation: $e');
    }
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _messages.add({"sender": "user", "text": message});
      _isLoading = true;
      _conversationStarted = true;
    });

    _messageController.clear();
    _scrollToBottom(force: false);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      // Add loading indicator message
      setState(() {
        _messages.add({
          "sender": "assistant",
          "text": "",
          "fullText": "",
          "displayText": "",
          "isTyping": false,
          "isLoading": true, // new: loading state
        });
        _isLoading = true;
      });

      // Check if user is near bottom and show jump button if not
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        final isNear = (pos.maxScrollExtent - pos.pixels) <= _bottomThreshold;
        if (!isNear) {
          setState(() {
            _showScrollToBottom = true;
          });
        }
      });

      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/conversation/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          "Content-Type": "application/json",
          "ngrok-skip-browser-warning": "true",
        },
        body: jsonEncode({
          'userId': widget.userId,
          'message': message,
          'conversationId': _conversationId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawResponse = data['reply'] ?? 'No response received.';
        final aiResponse = sanitizeUtf16(rawResponse);

        // Replace loading message with actual response
        setState(() {
          _messages.last = {
            "sender": "assistant",
            "text": aiResponse,
            "fullText": aiResponse,
            "displayText": "",
            "isTyping": true,
            "isLoading": false, // done loading
          };
          _isLoading = false;
        });

        // Auto-scroll if user is near bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          final pos = _scrollController.position;
          final isNear = (pos.maxScrollExtent - pos.pixels) <= _bottomThreshold;
          if (isNear) {
            _scrollToBottom(force: false);
          }
        });

        await _typeMessage(_messages.last);
        await _saveConversationToDatabase(_messages);
      } else {
        setState(() {
          _isLoading = false;
          _messages.removeLast(); // remove loading message on error
        });
        throw Exception('Failed to get AI response: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        if (_messages.isNotEmpty && _messages.last['isLoading'] == true) {
          _messages.removeLast(); // remove loading message
        }
      });
      debugPrint('Error in _sendMessage: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send message. Please try again.'),
        ),
      );
    }
  }

  Future<void> _typeMessage(Map<String, dynamic> botMessage) async {
    String fullText = botMessage['fullText'];
    String displayText = '';
    int index = 0;

    while (index < fullText.length && mounted) {
      setState(() {
        displayText += fullText[index];
        botMessage['displayText'] = displayText;
        botMessage['isTyping'] = index < fullText.length - 1;
      });
      // remove: _scrollToBottom(); -- let user scroll freely
      await Future.delayed(const Duration(milliseconds: 20));
      index++;
    }

    if (mounted) {
      setState(() {
        botMessage['isTyping'] = false;
      });
    }
  }

  Future<void> _startNewConversation() async {
    setState(() {
      _messages.clear();
      _conversationStarted = false;
      _conversationId = null;
      _conversationTitle = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/api/conversation/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          "Content-Type": "application/json",
          "ngrok-skip-browser-warning": "true",
        },
        body: jsonEncode({
          'userId': widget.userId,
          'message': {'sender': 'assistant', 'text': 'Conversation started'},
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        setState(() {
          _conversationId = data['_id'];
          _conversationTitle = data['title'];
          _conversationStarted = false;
        });
        await _loadConversationList();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New conversation started')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start new conversation')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error. Try again.')),
      );
    }
  }

  Future<void> _loadConversationList() async {
    if (!mounted) return;
    setState(() => _isLoadingList = true);
    try {
      final list = await ApiService.fetchConversationList(widget.userId);
      if (mounted) {
        setState(() {
          _conversationList = List<Map<String, dynamic>>.from(list);
        });
      }
    } catch (e) {
      debugPrint('load list error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingList = false);
    }
  }

  Future<void> _loadConversation(String convId) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.fetchConversation(convId);
      final messages = data['messages'] as List<dynamic>;

      final formatted = messages.map((m) {
        final role = m['role'] ?? m['sender'] ?? 'user';
        final rawtext = m['content'] ?? m['text'] ?? '';
        final text = sanitizeUtf16(rawtext);
        return {
          "sender": role == "assistant" ? "assistant" : "user",
          "text": text,
          "fullText": text,
          "displayText": text,
          "isTyping": false,
        };
      }).toList();

      setState(() {
        _conversationId = convId;
        _conversationTitle = data['title'];
        _messages.clear();
        _messages.addAll(formatted);
        _conversationStarted = true;
        _isLoading = false;
      });
      _scrollToBottom(force: true);
    } catch (e) {
      debugPrint('load conv error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _renameConversation(String convId, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Conversation'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter new title',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newTitle == null || newTitle.isEmpty || newTitle == currentTitle)
      return;

    try {
      final token = await SharedPreferences.getInstance().then(
        (p) => p.getString('jwt_token'),
      );
      final uri = Uri.parse(
        '${ApiConstants.baseUrl}/api/conversation/$convId/rename',
      );

      final resp = await http.put(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'title': newTitle}),
      );

      if (resp.statusCode == 200) {
        await _loadConversationList();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Renamed to "$newTitle"')));
      } else {
        throw Exception(resp.body);
      }
    } catch (e) {
      debugPrint('Rename error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to rename')));
    }
  }

  Widget _buildChatItem(BuildContext context, String title, String convId) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: const Icon(Icons.chat_bubble_outline, size: 20),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, color: Colors.black87),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          Navigator.pop(context);
          _loadConversation(convId);
        },
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18, color: Colors.black54),
          onSelected: (value) async {
            if (value == 'delete') {
              final token = await SharedPreferences.getInstance().then(
                (p) => p.getString('jwt_token'),
              );
              await http.delete(
                Uri.parse('${ApiConstants.baseUrl}/api/conversation/$convId'),
                headers: {'Authorization': 'Bearer $token'},
              );
              _loadConversationList();
            } else if (value == 'rename') {
              await _renameConversation(convId, title);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFE0F2F1),
      drawer: SidebarDrawer(
        userName: _userName,
        userAvatar: _userAvatar ?? '',
        userId: widget.userId,
        onShowSettings: _showSettingsMenu,
        onNewConversation: _startNewConversation,
        conversationList: _conversationList,
        isLoadingList: _isLoadingList,
        buildChatItem: _buildChatItem,
        searchController: _sidebarSearchController,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFB2DFDB),
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      icon: const Icon(
                        Icons.menu,
                        color: Color(0xFF37474F),
                        size: 24,
                      ),
                    ),
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/pickwise_logo_middle_rmbg.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Pickwise',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF37474F),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.remove("jwt_token");
                            Navigator.of(context).pushNamedAndRemoveUntil(
                              '/login',
                              (route) => false,
                            );
                          },
                          icon: (_userAvatar != null && _userAvatar!.isNotEmpty)
                              ? CircleAvatar(
                                  backgroundImage: NetworkImage(_userAvatar!),
                                  radius: 20,
                                )
                              : CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFF707274),
                                  child: Text(
                                    _userName.isNotEmpty
                                        ? _userName[0].toUpperCase()
                                        : "?",
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Main Chat Area (wrap with Stack to overlay "jump to bottom" button)
            Expanded(
              child: Stack(
                children: [
                  RepaintBoundary(
                    key: _chatBoundaryKey,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: _conversationStarted
                          ? ListView.builder(
                              controller: _scrollController,
                              itemCount: _messages.length,
                              physics: const BouncingScrollPhysics(),
                              itemBuilder: (context, index) {
                                final msg = _messages[index];
                                final isUser = msg['sender'] == 'user';

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: isUser
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        child: Stack(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isUser
                                                    ? const Color(0xFF4DD0E1)
                                                    : const Color(0xFFF5F5F5),
                                                borderRadius: BorderRadius.only(
                                                  topLeft:
                                                      const Radius.circular(16),
                                                  topRight:
                                                      const Radius.circular(16),
                                                  bottomLeft: Radius.circular(
                                                    isUser ? 16 : 4,
                                                  ),
                                                  bottomRight: Radius.circular(
                                                    isUser ? 4 : 16,
                                                  ),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.05),
                                                    blurRadius: 4,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: isUser
                                                  ? Text(
                                                      msg['text'] ?? '',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                      ),
                                                    )
                                                  : (msg['isLoading'] ?? false)
                                                  ? const LoadingDotsWidget()
                                                  : BotMessageWidget(
                                                      fullText:
                                                          msg['fullText'] ??
                                                          msg['text'] ??
                                                          '',
                                                      displayText:
                                                          msg['displayText'] ??
                                                          msg['fullText'] ??
                                                          msg['text'] ??
                                                          '',
                                                      isTyping:
                                                          msg['isTyping'] ??
                                                          false,
                                                    ),
                                            ),
                                            if (!(msg['isTyping'] ?? false) &&
                                                !(msg['isLoading'] ?? false))
                                              Positioned(
                                                top: 4,
                                                right: 4,
                                                child: GestureDetector(
                                                  onTap: () => _copyMessage(
                                                    isUser
                                                        ? (msg['text'] ?? '')
                                                        : (msg['fullText'] ??
                                                              msg['text'] ??
                                                              ''),
                                                  ),
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withOpacity(0.8),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.copy,
                                                      size: 16,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            )
                          : Center(child: WelcomeMessage(userName: _userName)),
                    ),
                  ),

                  // Jump-to-bottom button shown when new messages arrive and user scrolled up
                  if (_showScrollToBottom)
                    Positioned(
                      right: 20,
                      bottom: 110, // sits above the input bar
                      child: AnimatedOpacity(
                        opacity: _showScrollToBottom ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: FloatingActionButton.small(
                          backgroundColor: const Color(0xFF4DD0E1),
                          elevation: 8,
                          onPressed: () {
                            _scrollToBottom(force: true);
                          },
                          child: const Icon(
                            Icons.arrow_downward,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Input Bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: TextField(
                          controller: _messageController,
                          textInputAction:
                              TextInputAction.send, // new: enable Enter key
                          decoration: const InputDecoration(
                            hintText: 'Ask for Recommendation',
                            hintStyle: TextStyle(
                              color: Color(0xFF9E9E9E),
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                          onSubmitted: (_) => _sendMessage(
                            _messageController.text,
                          ), // existing: already wired
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4DD0E1),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4DD0E1).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        onPressed: () => _sendMessage(_messageController.text),
                        icon: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _sidebarSearchController.dispose();
    super.dispose();
  }
}

// --- Helper Widgets ---

class WelcomeMessage extends StatelessWidget {
  final String userName;
  const WelcomeMessage({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Hi, $userName!',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: Color(0xFF37474F),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'What can I help you?',
            style: TextStyle(
              fontSize: 18,
              color: Color(0xFF37474F),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class BotMessageWidget extends StatelessWidget {
  final String fullText;
  final String displayText;
  final bool isTyping;

  const BotMessageWidget({
    super.key,
    required this.fullText,
    required this.displayText,
    required this.isTyping,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeMarkdown(
          data: displayText,
          onTapLink: (text, href, title) {
            if (href == null || href.isEmpty) return;
            String? id;
            try {
              final uri = Uri.parse(href);
              if (uri.scheme == 'app' && uri.host == 'laptop') {
                id = uri.pathSegments.isNotEmpty
                    ? uri.pathSegments.first
                    : null;
              } else {
                // fallback: use last path segment
                if (uri.pathSegments.isNotEmpty) id = uri.pathSegments.last;
              }
            } catch (_) {
              final parts = href.split('/');
              if (parts.isNotEmpty) id = parts.last;
            }

            if (id != null && id.isNotEmpty) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LaptopDetailsPage(laptop: null, laptopId: id),
                ),
              );
            } else {
              // unrecognized link; ignore or implement external launch
            }
          },
        ),
        if (isTyping)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF4DD0E1)),
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  'Typing...',
                  style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 13),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class LoadingDotsWidget extends StatelessWidget {
  const LoadingDotsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF4DD0E1),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF4DD0E1),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF4DD0E1),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

// --- Sidebar Drawer ---

class SidebarDrawer extends StatelessWidget {
  final String userName;
  final String userAvatar;
  final String userId;
  final void Function(BuildContext)? onShowSettings;
  final VoidCallback? onNewConversation;
  final List<Map<String, dynamic>> conversationList;
  final bool isLoadingList;
  final Widget Function(BuildContext, String, String)? buildChatItem;
  final TextEditingController searchController;

  const SidebarDrawer({
    super.key,
    required this.userName,
    required this.userAvatar,
    required this.userId,
    this.onShowSettings,
    this.onNewConversation,
    required this.conversationList,
    required this.isLoadingList,
    this.buildChatItem,
    required this.searchController,
  });

  List<Map<String, dynamic>> _filterConversations(
    List<Map<String, dynamic>> list,
    String query,
  ) {
    if (query.isEmpty) return list;
    final q = query.toLowerCase();
    return list.where((conv) {
      final rawtitle = (conv['title'] ?? 'untitled').toString().toLowerCase();
      final title = sanitizeUtf16(rawtitle.toString()).toLowerCase();
      return title.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFE8E4E1),
      child: SafeArea(
        child: Column(
          children: [
            // SEARCH BAR WITH CLEAR BUTTON
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: searchController,
                        builder: (context, value, child) {
                          return Row(
                            children: [
                              const Icon(
                                Icons.search,
                                color: Color(0xFF9E9E9E),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: searchController,
                                  decoration: InputDecoration(
                                    hintText: 'Search',
                                    hintStyle: const TextStyle(
                                      color: Color(0xFF9E9E9E),
                                      fontSize: 14,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    suffixIcon: value.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.clear,
                                              size: 16,
                                            ),
                                            onPressed: () =>
                                                searchController.clear(),
                                          )
                                        : null,
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onNewConversation?.call();
                      },
                      icon: const Icon(Icons.add_comment_outlined),
                    ),
                  ),
                ],
              ),
            ),

            // BACK TO HOME
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ShoppingPage(
                      userId: userId,
                      userName: userName,
                      userAvatar: userAvatar,
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(280, 48),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.home, size: 20),
                  SizedBox(width: 8),
                  Text('Back To Home'),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // CHAT HEADER
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.black87,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Chat',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFFD0CCC7), thickness: 1),

            // CONVERSATION LIST (FILTERED)
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: searchController,
                builder: (context, value, child) {
                  final filtered = _filterConversations(
                    conversationList,
                    value.text,
                  );
                  return isLoadingList
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No conversations found',
                            style: TextStyle(
                              color: Colors.black54,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final conv = filtered[i];
                            return buildChatItem!(
                              context,
                              conv['title'] ?? 'Untitled',
                              conv['_id'].toString(),
                            );
                          },
                        );
                },
              ),
            ),

            // USER FOOTER
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFD0CCC7))),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF4A5568),
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => onShowSettings?.call(context),
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.black87,
                      size: 24,
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
}
