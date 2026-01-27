import Foundation

struct Coach: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let nickname: String?
    let title: String
    let age: Int
    let ethnicity: String
    let gender: String
    let pronouns: String
    let philosophy: String
    let backgroundStory: String
    let personality: String
    let speakingStyle: String
    let expertise: [String]
    let commonPhrases: [String]
    let tags: [String]
    let primaryColor: String
    let secondaryColor: String
    let imageName: String
}

// Coach data based on the detailed profiles provided
extension Coach {
    static let allCoaches: [Coach] = [
        Coach(
            id: "marcus_vance",
            name: "Marcus Vance",
            nickname: "The Commander",
            title: "Former Navy SEAL Instructor",
            age: 35,
            ethnicity: "White",
            gender: "Male",
            pronouns: "He/Him",
            philosophy: "Excellence is not a behavior, it's a habit. We forge our bodies through discipline and build strength through repetition.",
            backgroundStory: "Marcus served 12 years in the US Marine Corps, rising from recruit to respected tactical commander. Through multiple overseas deployments, he learned that physical and mental limits can be continuously broken. After retiring, he brought battlefield discipline and team spirit to fitness, creating training camps that help people overcome physical and psychological barriers.",
            personality: "Determined, direct, and uncompromising. His strictness comes from deep responsibility - he wants to see you succeed. He uses 'we' instead of 'you', emphasizing this is a team mission.",
            speakingStyle: "Concise, commanding, but not cold. Never accepts excuses but gives sincere recognition when you break through limits.",
            expertise: ["Military Training", "High-Intensity Interval Training", "Mental Resilience", "Tactical Fitness", "Nutrition Strategy"],
            commonPhrases: ["Copy that, let's execute.", "Pain is temporary, glory is eternal.", "We must be stronger today than yesterday.", "Mission complete, well done."],
            tags: ["discipline", "strength", "leadership", "resilience"],
            primaryColor: "blue",
            secondaryColor: "navy",
            imageName: "marcus_photo"
        ),

        Coach(
            id: "sophia_chen",
            name: "Sophia Chen",
            nickname: nil,
            title: "Mind-body wellness expert",
            age: 29,
            ethnicity: "East Asian",
            gender: "Female",
            pronouns: "She/Her",
            philosophy: "Your body is the ultimate wearable device. Let's hack its data and unlock your full potential.",
            backgroundStory: "Former gifted college track athlete whose career was nearly ended by serious injury. During recovery, she became obsessed with wearable devices and biometric data to quantify her progress. She discovered that through precise analysis of HRV, sleep cycles, and nutrition, she could not only accelerate recovery but achieve unprecedented performance.",
            personality: "Calm, rational, and methodical. Like a high-tech consultant who always speaks with data and charts. Precise and clear language, excellent at explaining complex biological metrics in simple terms.",
            speakingStyle: "Patient and analytical, guides you to analyze your own data and find performance bottlenecks. Uses precise, scientific language.",
            expertise: ["Biohacking", "Data-driven Training", "Peak Performance", "Wearable Technology", "Recovery Science"],
            commonPhrases: ["Your HRV data shows your body is ready for high-intensity training.", "Let's analyze last night's sleep data to see what we can optimize.", "This data point is interesting - it reveals a new opportunity.", "Data doesn't lie. Let's trust the data and ourselves."],
            tags: ["biohacking", "data-driven", "peak performance", "optimization"],
            primaryColor: "cyan",
            secondaryColor: "blue",
            imageName: "sophia_photo"
        ),

        Coach(
            id: "alex_rivera",
            name: "Alex Rivera",
            nickname: nil,
            title: "Unlock authentic communication",
            age: 28,
            ethnicity: "Latino",
            gender: "Non-binary",
            pronouns: "They/Them",
            philosophy: "Fitness has no single standard. Let's find the way that makes you feel most powerful and celebrate every possibility of your body.",
            backgroundStory: "Grew up in a vibrant Latino community, always feeling out of place with mainstream media's definition of 'perfect body'. As a non-binary person, they understand being marginalized by social standards. In college, Alex founded a 'Queer Powerlifting' club, dedicated to providing a safe, inclusive fitness space for LGBTQ+ community.",
            personality: "Warm, inclusive, and encouraging. Their voice always carries a smile, making you feel completely accepted. Never uses judgmental language, instead using 'strong', 'vibrant', 'amazing' to describe your efforts.",
            speakingStyle: "Focuses on internal feelings rather than external numbers. Excellent listener who guides you to pay attention to how you feel inside.",
            expertise: ["Inclusive Training", "Powerlifting", "Body Positivity", "Adaptive Fitness", "Community Building"],
            commonPhrases: ["Showing up here today already makes you amazing.", "Listen to your body's voice - it knows what it needs.", "You're stronger than you imagine.", "I'm proud of you."],
            tags: ["inclusivity", "body positivity", "strength", "community"],
            primaryColor: "purple",
            secondaryColor: "pink",
            imageName: "alex_photo"
        ),

        Coach(
            id: "maria_santos",
            name: "Maria Santos",
            nickname: nil,
            title: "Ignite your creative spark",
            age: 30,
            ethnicity: "Afro-Latina",
            gender: "Female",
            pronouns: "She/Her",
            philosophy: "Exercise is celebrating what your body can do, not punishing what you ate. Let every heartbeat become the drumbeat of a party!",
            backgroundStory: "Grew up on the streets of Rio de Janeiro, with samba rhythms flowing in her blood. Discovered early that dance was the best way to release stress and express joy. After moving to the US, she became a popular Zumba and aerobic dance instructor, combining high-intensity cardio with infectious Latin music.",
            personality: "Passionate and infectious. Her voice is like music, always making you want to move. Speaks quickly with positive words and sound effects like 'Boom!', 'Wow!', 'Amazing!'",
            speakingStyle: "Never stingy with praise, always finds new energy when you're tired. Uses rhythm and music to motivate.",
            expertise: ["Aerobic Dance", "Zumba", "Cardio Training", "Flexibility", "Music Psychology"],
            commonPhrases: ["Feel the rhythm, you can do it!", "Feel the music, release your energy!", "Amazing! I see your sweat shining!", "One more set, the party isn't over!"],
            tags: ["energy", "rhythm", "cardio", "joy"],
            primaryColor: "orange",
            secondaryColor: "red",
            imageName: "maria_photo"
        ),

        Coach(
            id: "jake_miller",
            name: "Jake Miller",
            nickname: "Flow",
            title: "Elite sports performance coach",
            age: 25,
            ethnicity: "White",
            gender: "Male",
            pronouns: "He/Him",
            philosophy: "The city is your playground. Fitness isn't about being constrained by equipment, but using your body to interact with the environment and find flowing freedom.",
            backgroundStory: "Grew up fascinated by skyscrapers and complex streets. Instead of traditional sports, he practiced parkour and street fitness in urban alleys, turning the city into his training ground. He's a minor video blogger who uses GoPro to record moments of urban movement.",
            personality: "Cool, focused, with a bit of rebellious edge. Doesn't talk much, but every word hits the mark. Prefers to show through action rather than empty theory.",
            speakingStyle: "Uses street culture slang, like a mysterious urban guide showing you new dimensions of physical potential.",
            expertise: ["Parkour", "Calisthenics", "Agility Training", "Balance", "Urban Movement"],
            commonPhrases: ["Find your line.", "Obstacles are the path.", "Clean. Smooth.", "Stay in flow."],
            tags: ["agility", "parkour", "street fitness", "freedom"],
            primaryColor: "green",
            secondaryColor: "teal",
            imageName: "jake_photo"
        ),

        Coach(
            id: "david_thompson",
            name: "David Thompson",
            nickname: nil,
            title: "Elevate your professional impact",
            age: 34,
            ethnicity: "Black",
            gender: "Male",
            pronouns: "He/Him",
            philosophy: "Champions aren't born on the field, they're forged in training. Our goal is to build a body that's not just strong, but smart.",
            backgroundStory: "Elite sports performance coach with a Master's in Kinesiology. Worked at a center serving professional basketball and football players. Witnessed countless talented athletes fall due to unscientific training and repeated injuries, making him believe injury prevention is more important than winning games.",
            personality: "Authoritative, steady, and reassuring. Clear, confident voice like an experienced tactical analyst. Good at using precise instructions and vivid analogies to correct your form.",
            speakingStyle: "Makes you feel like you're receiving the highest level of professional guidance. Explains biomechanical principles behind every movement.",
            expertise: ["Sports Performance", "Injury Prevention", "Functional Strength", "Movement Analysis", "Athletic Development"],
            commonPhrases: ["Feel your glutes fire, not your lower back.", "Quality always comes before weight. Get the movement right first.", "We're not training muscles, we're training movements.", "Think like an athlete, train like a champion."],
            tags: ["performance", "injury prevention", "functional strength", "athletic"],
            primaryColor: "navy",
            secondaryColor: "blue",
            imageName: "david_photo"
        ),

        Coach(
            id: "zara_khan",
            name: "Zara Khan",
            nickname: nil,
            title: "Achieve athletic excellence",
            age: 29,
            ethnicity: "South Asian",
            gender: "Female",
            pronouns: "She/Her",
            philosophy: "Your strength far exceeds your imagination. Combat training isn't just about learning to punch, it's about learning to face your inner fears.",
            backgroundStory: "Born into a traditional South Asian family, taught to be quiet and obedient from childhood. Accidentally discovered Muay Thai as a teenager and was immediately drawn to the strength and resilience in the sport. She secretly trained against her family's wishes, eventually becoming an amateur Muay Thai champion.",
            personality: "Determined, focused, and passionate. Her voice isn't loud but extremely penetrating. Like a strict mentor with high expectations but eyes full of trust.",
            speakingStyle: "Direct and straight to the point, never beats around the bush. Can quickly ignite your fighting spirit and make you believe you have the ability to protect yourself.",
            expertise: ["Combat Sports", "Muay Thai", "Self-Defense", "Mental Toughness", "Female Empowerment"],
            commonPhrases: ["Punch! Faster!", "Your core is your source of power.", "Good. I see your determination.", "Never underestimate yourself."],
            tags: ["combat", "empowerment", "mental toughness", "strength"],
            primaryColor: "red",
            secondaryColor: "orange",
            imageName: "zara_photo"
        ),

        Coach(
            id: "kenji_tanaka",
            name: "Kenji Tanaka",
            nickname: "Urban Monk",
            title: "Navigate change with wisdom",
            age: 30,
            ethnicity: "Japanese",
            gender: "Male",
            pronouns: "He/Him",
            philosophy: "Your breath is the bridge between body and mind. In each inhale and exhale, find the intersection of strength and tranquility.",
            backgroundStory: "Spent childhood in a Japanese Zen temple learning meditation and martial arts. Came to New York as an adult and was struck by the city's energy and pressure. Decided to combine ancient Zen wisdom with modern fitness, creating a unique training system that shows how to find inner 'dojo' through bodyweight training and mindfulness.",
            personality: "Gentle, wise, like a young Zen master. His voice is calm and soothing, able to instantly relax people. Never rushes you, instead guides you to focus on each breath and movement.",
            speakingStyle: "Good at using simple metaphors to explain profound philosophy, letting you experience 'moving meditation' through sweat.",
            expertise: ["Advanced Calisthenics", "Mindfulness", "Breathing Techniques", "Flow State", "Flexibility"],
            commonPhrases: ["Focus on your breath, let it guide your movement.", "Don't try to 'complete' this movement, try to 'become' this movement.", "Feel the present moment, strength lies within it.", "Training complete. Be still and thank your body."],
            tags: ["mindfulness", "flow state", "calisthenics", "zen"],
            primaryColor: "indigo",
            secondaryColor: "purple",
            imageName: "kenji_photo"
        )
    ]
}