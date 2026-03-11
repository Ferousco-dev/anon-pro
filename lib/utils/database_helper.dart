import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';

class DatabaseHelper {
  static Database? _database;

  static const String postsTable = 'posts';
  static const String usersTable = 'users';
  static const String commentsTable = 'comments';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'anonpro.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $usersTable (
        id TEXT PRIMARY KEY,
        email TEXT,
        alias TEXT,
        display_name TEXT,
        bio TEXT,
        profile_image_url TEXT,
        cover_image_url TEXT,
        role TEXT,
        is_banned INTEGER,
        is_verified INTEGER,
        followers_count INTEGER,
        following_count INTEGER,
        posts_count INTEGER,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE $commentsTable (
        id TEXT PRIMARY KEY,
        post_id TEXT,
        user_id TEXT,
        content TEXT,
        is_anonymous INTEGER,
        created_at TEXT
      )
    ''');
  }

  Future<void> insertPosts(List<PostModel> posts) async {
    final db = await database;
    for (var post in posts) {
      await db.insert(
          postsTable,
          {
            'id': post.id,
            'user_id': post.userId,
            'content': post.content,
            'image_url': post.imageUrl,
            'is_anonymous': post.isAnonymous ? 1 : 0,
            'likes_count': post.likesCount,
            'comments_count': post.commentsCount,
            'shares_count': post.sharesCount,
            'views_count': post.viewsCount,
            'created_at': post.createdAt.toIso8601String(),
            'updated_at': post.updatedAt.toIso8601String(),
            'original_post_id': post.originalPostId,
            'reposts_count': post.repostsCount,
            'original_content': post.originalContent,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      if (post.user != null) {
        await insertUser(post.user!);
      }
    }
  }

  Future<void> insertUser(UserModel user) async {
    final db = await database;
    await db.insert(
        usersTable,
        {
          'id': user.id,
          'email': user.email,
          'alias': user.alias,
          'display_name': user.displayName,
          'bio': user.bio,
          'profile_image_url': user.profileImageUrl,
          'cover_image_url': user.coverImageUrl,
          'role': user.role,
          'is_banned': user.isBanned ? 1 : 0,
          'is_verified': user.isVerified ? 1 : 0,
          'followers_count': user.followersCount,
          'following_count': user.followingCount,
          'posts_count': user.postsCount,
          'created_at': user.createdAt?.toIso8601String(),
          'updated_at': user.updatedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PostModel>> getCachedPosts() async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query(postsTable, orderBy: 'created_at DESC', limit: 50);
    return List.generate(maps.length, (i) {
      return PostModel.fromJson(maps[i]);
    });
  }

  Future<UserModel?> getCachedUser(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query(usersTable, where: 'id = ?', whereArgs: [id]);
    if (maps.isNotEmpty) {
      return UserModel.fromJson(maps.first);
    }
    return null;
  }

  Future<void> insertComments(List<Map<String, dynamic>> comments) async {
    final db = await database;
    for (var comment in comments) {
      await db.insert(
          commentsTable,
          {
            'id': comment['id'],
            'post_id': comment['post_id'],
            'user_id': comment['user_id'],
            'content': comment['content'],
            'is_anonymous': comment['is_anonymous'] == true ? 1 : 0,
            'created_at': comment['created_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<Map<String, dynamic>>> getCachedComments(String postId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(commentsTable,
        where: 'post_id = ?', whereArgs: [postId], orderBy: 'created_at ASC');
    return maps;
  }
}
