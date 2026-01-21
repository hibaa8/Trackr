//
//  HealthKitManager.swift
//  AITrainer
//
//  HealthKit integration for fitness and health data
//

import Foundation
import HealthKit
import Combine

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
