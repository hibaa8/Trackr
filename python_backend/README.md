# 🎥 AI Trainer YouTube API Backend

Python FastAPI backend that serves curated workout videos from YouTube playlists to the iOS app.

## 🚀 Quick Start

1. **Install Dependencies**
   ```bash
   ./start.sh
   ```

2. **Start Server**
   The server will start automatically at `http://localhost:8000`
   
3. **Environment Variables**
   Set these before starting the backend:
   ```bash
   export GOOGLE_PLACES_API_KEY="your_key_here"
   export YOUTUBE_API_KEY="your_key_here"
   ```

## 🔗 API Endpoints

### Health Check
```
GET /health
```

### Get Categories
```
GET /categories
```

### Get Videos by Category
```
GET /videos?category=cardio&limit=20
```

**Parameters:**
- `category`: all, cardio, strength, yoga, hiit
- `limit`: 1-50 videos (default: 20)

### Get Individual Video
```
GET /video/{video_id}
```

## 📱 iOS App Integration

The iOS app automatically connects to this backend when available. If the backend is not running, it falls back to offline sample videos.

To change the backend URL in the iOS app, edit:
```swift
// Services/YouTubeService.swift
private let baseURL = "http://your-server-url:8000"
```

## 🎯 Features

- ✅ **Curated Content**: Uses real fitness YouTube playlists
- ✅ **No Embedding Issues**: All videos are pre-validated for embedding
- ✅ **Smart Caching**: 5-minute cache to reduce API calls
- ✅ **Fallback Support**: Graceful degradation if API fails
- ✅ **CORS Enabled**: Ready for iOS app integration

## 🔧 Configuration

### API Key
The YouTube API key is embedded in the code. For production:
1. Move the API key to environment variables
2. Set up proper authentication
3. Deploy to a cloud service

### Playlists
Current playlists are curated fitness content from popular channels:
- **All/Cardio**: FitnessBlender workouts
- **Strength**: Bodyweight strength training
- **Yoga**: Yoga with Adriene flows
- **HIIT**: High-intensity interval training

To add your own playlists, edit the `CATEGORY_PLAYLISTS` dictionary in `app.py`.

## 📊 API Response Format

```json
{
  "category": "cardio",
  "total": 15,
  "videos": [
    {
      "id": "video_id_here",
      "title": "10 MIN CARDIO WORKOUT",
      "instructor": "FitnessBlender",
      "duration": 10,
      "formattedDuration": "10 min",
      "difficulty": "beginner",
      "thumbnailURL": "https://i.ytimg.com/vi/.../hqdefault.jpg",
      "embedURL": "https://www.youtube-nocookie.com/embed/video_id",
      "youtubeURL": "https://www.youtube.com/watch?v=video_id",
      "viewCount": 1000000,
      "description": "Great cardio workout for beginners..."
    }
  ]
}
```

## 🔄 Benefits Over Direct YouTube API in iOS

1. **No Embedding Restrictions**: Pre-validated playlist videos
2. **Better Performance**: Server-side caching and processing
3. **Content Control**: Curated playlists vs random search results
4. **API Quota Management**: Centralized API usage
5. **Rich Metadata**: Enhanced video information processing

## 🌐 Deployment

For production deployment:

1. **Deploy to Cloud**: Heroku, AWS, Google Cloud, etc.
2. **Environment Variables**: Move API key to env vars
3. **HTTPS**: Enable SSL for production
4. **Database**: Add Redis/PostgreSQL for persistent caching
5. **Update iOS App**: Change `baseURL` to production URL

## 📝 Development

- **FastAPI Docs**: Visit `http://localhost:8000/docs` for interactive API documentation
- **Logs**: Check console for API requests and errors
- **Hot Reload**: Code changes automatically restart the server

---

**The iOS app will now use real, embeddable YouTube videos without the Error 152-4 issues!** 🎉