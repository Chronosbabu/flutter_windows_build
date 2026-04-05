import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'video_player_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(backgroundColor: Colors.black, elevation: 0),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<dynamic> videos = [];
  List<dynamic> filteredVideos = [];
  Map<String, dynamic>? featuredVideo;
  bool isLoading = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool isSearching = false;

  // ================== CONFIGURATION (compatible Windows) ==================
  // Si tu lances le serveur sur la même machine Windows → utilise "http://127.0.0.1:5000"
  // Sinon garde ton IP actuelle (172.20.10.10)
  static const String SERVER_URL = "http://172.20.10.10:5000";
  // =====================================================================

  @override
  void initState() {
    super.initState();
    fetchVideos();
    _searchController.addListener(_onSearchChanged);
    _searchFocus.addListener(() {
      setState(() => isSearching = _searchFocus.hasFocus || _searchController.text.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      isSearching = query.isNotEmpty || _searchFocus.hasFocus;
      filteredVideos = query.isEmpty
          ? List.from(videos)
          : videos.where((v) => v['name'].toString().toLowerCase().contains(query)).toList();
    });
  }

  void fetchVideos() async {
    setState(() => isLoading = true);

    try {
      final response = await http
          .get(Uri.parse("$SERVER_URL/videos"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          videos = data;
          filteredVideos = List.from(videos);
          if (videos.isNotEmpty) {
            featuredVideo = videos[math.Random().nextInt(videos.length)];
          }
        });
        print("✅ ${videos.length} vidéos chargées avec succès");
      } else {
        print("❌ Erreur serveur : ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("❌ Impossible de joindre le serveur : $e");
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => isSearching = false);
    _searchFocus.unfocus();
  }

  // Widget image réseau ultra-stable (plus jamais d'erreur 404 dans la console)
  Widget _buildNetworkImage(String url, {double? height, BoxFit fit = BoxFit.cover}) {
    return Image.network(
      url,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Colors.grey[850],
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.broken_image, color: Colors.white54, size: 50),
                SizedBox(height: 8),
                Text("Image non disponible", style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (isSearching) {
          _clearSearch();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text("IPTV"),
          backgroundColor: Colors.black,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: fetchVideos,
            ),
          ],
        ),
        body: Column(
          children: [
            // Barre de recherche
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.black,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: "Rechercher...",
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white54),
                    onPressed: _clearSearch,
                  )
                      : null,
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Vidéo mise en avant
            if (!isSearching && featuredVideo != null)
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(
                      url: featuredVideo!['url'],
                      name: featuredVideo!['name'],
                    ),
                  ),
                ).then((_) => fetchVideos()),
                child: Stack(
                  children: [
                    _buildNetworkImage(
                      featuredVideo!['thumbnail'],
                      height: 280,
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 160,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.transparent, Colors.black],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 50,
                      left: 20,
                      right: 20,
                      child: Text(
                        featuredVideo!['name'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(blurRadius: 12, color: Colors.black)],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 45,
                      right: 30,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE50914),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, size: 40, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

            // Liste des vidéos
            Expanded(
              child: isLoading && videos.isEmpty
                  ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              )
                  : RefreshIndicator(
                onRefresh: () async => fetchVideos(),
                child: filteredVideos.isEmpty
                    ? const Center(
                  child: Text(
                    "Aucun résultat trouvé",
                    style: TextStyle(color: Colors.white54, fontSize: 18),
                  ),
                )
                    : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: filteredVideos.length,
                  itemBuilder: (context, index) {
                    final video = filteredVideos[index];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(
                            url: video['url'],
                            name: video['name'],
                          ),
                        ),
                      ).then((_) => fetchVideos()),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildNetworkImage(video['thumbnail']),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.transparent, Colors.black87],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                                child: Text(
                                  video['name'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}