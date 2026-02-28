//
//  HealthKitManager.swift
//  AITrainer
//
//  HealthKit integration for fitness and health data
//

import Foundation
import HealthKit
import Combine

struct HealthDaySnapshot {
    let date: String
    let steps: Int
    let caloriesBurned: Int
    let activeMinutes: Int
    let workoutsSummary: String
}

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var todaySteps: Int = 0
    @Published var todayCaloriesBurned: Int = 0
    @Published var todayActiveMinutes: Int = 0
    @Published var recentWorkouts: [HKWorkout] = []
    
    // HealthKit data types we want to read
    private let readTypes: Set<HKObjectType> = {
        guard let stepCount = HKObjectType.quantityType(forIdentifier: .stepCount),
              let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let exerciseTime = HKObjectType.quantityType(forIdentifier: .appleExerciseTime),
              let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass),
              let height = HKObjectType.quantityType(forIdentifier: .height),
              let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return []
        }
        
        return [
            stepCount,
            activeEnergy,
            exerciseTime,
            bodyMass,
            height,
            heartRate,
            HKObjectType.workoutType()
        ]
    }()
    
    // HealthKit data types we want to write
    private let writeTypes: Set<HKSampleType> = {
        guard let activeEnergy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) else {
            return []
        }
        
        return [
            activeEnergy,
            bodyMass,
            HKObjectType.workoutType()
        ]
    }()
    
    init() {
        checkHealthKitAvailability()
    }
    
    // MARK: - Authorization
    
    private func checkHealthKitAvailability() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit is not available on this device")
            return
        }
    }
    
    func requestAuthorization() {
        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.isAuthorized = true
                    self?.fetchTodayData()
                } else if let error = error {
                    print("HealthKit authorization failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Fetch Data
    
    func fetchTodayData() {
        fetchSteps()
        fetchCaloriesBurned()
        fetchActiveMinutes()
        fetchRecentWorkouts()
    }

    func collectDailySnapshots(lastDays: Int = 7, completion: @escaping ([HealthDaySnapshot]) -> Void) {
        let safeDays = max(1, min(31, lastDays))
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -(safeDays - 1), to: calendar.startOfDay(for: endDate)) else {
            completion([])
            return
        }

        var stepsByDay: [String: Int] = [:]
        var caloriesByDay: [String: Int] = [:]
        var minutesByDay: [String: Int] = [:]
        var workoutsByDay: [String: [String]] = [:]
        let group = DispatchGroup()

        group.enter()
        fetchDailyTotals(identifier: .stepCount, unit: HKUnit.count(), startDate: startDate, endDate: endDate) { values in
            stepsByDay = values
            group.leave()
        }

        group.enter()
        fetchDailyTotals(identifier: .activeEnergyBurned, unit: HKUnit.kilocalorie(), startDate: startDate, endDate: endDate) { values in
            caloriesByDay = values
            group.leave()
        }

        group.enter()
        fetchDailyTotals(identifier: .appleExerciseTime, unit: HKUnit.minute(), startDate: startDate, endDate: endDate) { values in
            minutesByDay = values
            group.leave()
        }

        group.enter()
        fetchWorkoutsByDay(startDate: startDate, endDate: endDate) { values in
            workoutsByDay = values
            group.leave()
        }

        group.notify(queue: .main) {
            var snapshots: [HealthDaySnapshot] = []
            for offset in 0..<safeDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
                let dayKey = formatter.string(from: day)
                let workoutSummary = (workoutsByDay[dayKey] ?? []).joined(separator: ", ")
                snapshots.append(
                    HealthDaySnapshot(
                        date: dayKey,
                        steps: stepsByDay[dayKey] ?? 0,
                        caloriesBurned: caloriesByDay[dayKey] ?? 0,
                        activeMinutes: minutesByDay[dayKey] ?? 0,
                        workoutsSummary: workoutSummary
                    )
                )
            }
            completion(snapshots)
        }
    }
    
    private func fetchSteps() {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, error in
            guard let result = result, let sum = result.sumQuantity() else {
                if let error = error {
                    print("Error fetching steps: \(error.localizedDescription)")
                }
                return
            }
            
            let steps = Int(sum.doubleValue(for: HKUnit.count()))
            DispatchQueue.main.async {
                self?.todaySteps = steps
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchCaloriesBurned() {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, error in
            guard let result = result, let sum = result.sumQuantity() else {
                if let error = error {
                    print("Error fetching calories: \(error.localizedDescription)")
                }
                return
            }
            
            let calories = Int(sum.doubleValue(for: HKUnit.kilocalorie()))
            DispatchQueue.main.async {
                self?.todayCaloriesBurned = calories
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchActiveMinutes() {
        guard let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else { return }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: exerciseType, quantitySamplePredicate: predicate, options: .cumulativeSum) { [weak self] _, result, error in
            guard let result = result, let sum = result.sumQuantity() else {
                if let error = error {
                    print("Error fetching exercise time: \(error.localizedDescription)")
                }
                return
            }
            
            let minutes = Int(sum.doubleValue(for: HKUnit.minute()))
            DispatchQueue.main.async {
                self?.todayActiveMinutes = minutes
            }
        }
        
        healthStore.execute(query)
    }
    
    private func fetchRecentWorkouts() {
        let workoutType = HKObjectType.workoutType()
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: workoutType, predicate: nil, limit: 10, sortDescriptors: [sortDescriptor]) { [weak self] _, samples, error in
            guard let workouts = samples as? [HKWorkout] else {
                if let error = error {
                    print("Error fetching workouts: \(error.localizedDescription)")
                }
                return
            }
            
            DispatchQueue.main.async {
                self?.recentWorkouts = workouts
            }
        }
        
        healthStore.execute(query)
    }

    private func fetchDailyTotals(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date,
        completion: @escaping ([String: Int]) -> Void
    ) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            completion([:])
            return
        }
        let calendar = Calendar.current
        var interval = DateComponents()
        interval.day = 1
        let anchor = calendar.startOfDay(for: startDate)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        let query = HKStatisticsCollectionQuery(
            quantityType: quantityType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: interval
        )

        query.initialResultsHandler = { _, results, error in
            guard let collection = results else {
                if let error {
                    print("Error fetching daily totals for \(identifier.rawValue): \(error.localizedDescription)")
                }
                completion([:])
                return
            }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            var values: [String: Int] = [:]
            collection.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                let key = formatter.string(from: stats.startDate)
                let amount = Int(stats.sumQuantity()?.doubleValue(for: unit) ?? 0)
                values[key] = amount
            }
            completion(values)
        }

        healthStore.execute(query)
    }

    private func fetchWorkoutsByDay(
        startDate: Date,
        endDate: Date,
        completion: @escaping ([String: [String]]) -> Void
    ) {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
            guard let workouts = samples as? [HKWorkout] else {
                if let error {
                    print("Error fetching workouts by day: \(error.localizedDescription)")
                }
                completion([:])
                return
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            var values: [String: [String]] = [:]
            for workout in workouts {
                let key = formatter.string(from: workout.startDate)
                let name = self.workoutName(for: workout)
                values[key, default: []].append(name)
            }
            completion(values)
        }

        healthStore.execute(query)
    }

    private func workoutName(for workout: HKWorkout) -> String {
        let base = workout.workoutActivityType.name
        let minutes = max(1, Int(workout.duration / 60))
        return "\(base) \(minutes) min"
    }
    
    // MARK: - Write Data
    
    func saveWorkout(type: HKWorkoutActivityType, start: Date, end: Date, calories: Double) {
        let workout = HKWorkout(activityType: type,
                               start: start,
                               end: end,
                               duration: end.timeIntervalSince(start),
                               totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                               totalDistance: nil,
                               metadata: nil)
        
        healthStore.save(workout) { success, error in
            if success {
                print("Workout saved successfully")
            } else if let error = error {
                print("Error saving workout: \(error.localizedDescription)")
            }
        }
    }
    
    func saveWeight(weight: Double, date: Date = Date()) {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        
        let weightQuantity = HKQuantity(unit: .pound(), doubleValue: weight)
        let weightSample = HKQuantitySample(type: weightType, quantity: weightQuantity, start: date, end: date)
        
        healthStore.save(weightSample) { success, error in
            if success {
                print("Weight saved successfully")
            } else if let error = error {
                print("Error saving weight: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Background Updates
    
    func enableBackgroundDelivery() {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return
        }
        
        healthStore.enableBackgroundDelivery(for: stepType, frequency: .hourly) { success, error in
            if let error = error {
                print("Error enabling background delivery for steps: \(error.localizedDescription)")
            }
        }
        
        healthStore.enableBackgroundDelivery(for: energyType, frequency: .hourly) { success, error in
            if let error = error {
                print("Error enabling background delivery for energy: \(error.localizedDescription)")
            }
        }
    }
}

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .traditionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .functionalStrengthTraining: return "Functional Strength"
        case .yoga: return "Yoga"
        case .swimming: return "Swimming"
        default: return "Workout"
        }
    }
}
