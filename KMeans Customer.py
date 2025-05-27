import pandas as pd
import numpy as np
import os
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime

# Define the full path to your CSV file
current_dir = os.path.dirname(os.path.abspath(__file__))
csv_path = os.path.join(current_dir, 'Customer Data Original.csv')

# Load the data
df = pd.read_csv(csv_path)

# Remove rows where CltID is blank (handles both empty strings and NaN)
df = df[df['CltID'].notna() & (df['CltID'] != '')]
after_cltid_count = len(df)
print(f"Rows after removing blank CltID: {after_cltid_count}")

# Data preprocessing

# Select features for clustering
# Modify these columns based on your actual CSV structure
features = ['DaysSinceLastVisit','CustomerTenureDays','BasketDiversity','AvgSpendPerVisit','AvgDaysBetweenVisits','TtlSpend','Last3MonthsGrowthRatio','Last6MonthsGrowthRatio','Last3MonthsVisitsGrowthRatio']

# Only remove rows with missing values in the feature columns
df = df.dropna(subset=features)
final_count = len(df)
print(f"Final row count after removing rows with missing features: {final_count}")
print(f"Removed {after_cltid_count - final_count} rows with missing feature values")

X = df[features]

# Analyze feature correlations
correlation_matrix = df[features].corr()

# Plot correlation heatmap
plt.figure(figsize=(10, 8))
sns.heatmap(correlation_matrix, annot=True, cmap='coolwarm', center=0)
plt.title('Feature Correlation Matrix')
plt.show()

# Standardize the features
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# Calculate variance of scaled features
feature_variance = pd.DataFrame(
    {'Feature': features,
     'Variance': np.var(X_scaled, axis=0)
    }).sort_values('Variance', ascending=False)

print("\nFeature Variance (after scaling):")
print("=================================")
for idx, row in feature_variance.iterrows():
    print(f"• {row['Feature']}: {row['Variance']:.3f}")

# Determine optimal number of clusters using elbow method
inertias = []
K = range(1, 11)

for k in K:
    kmeans = KMeans(n_clusters=k, random_state=42)
    kmeans.fit(X_scaled)
    inertias.append(kmeans.inertia_)

# Plot elbow curve
plt.figure(figsize=(10, 6))
plt.plot(K, inertias, 'bx-')
plt.xlabel('k')
plt.ylabel('Inertia')
plt.title('Elbow Method For Optimal k')
plt.show()

# Perform K-means clustering with optimal k (let's use 5 clusters)
optimal_k = 5
kmeans = KMeans(n_clusters=optimal_k, random_state=42)
df['Cluster'] = kmeans.fit_predict(X_scaled)

# Visualize the clusters (using first two features)
plt.figure(figsize=(12, 8))
scatter = plt.scatter(X[features[0]], X[features[1]], 
                     c=df['Cluster'], cmap='viridis')
plt.xlabel(features[0])
plt.ylabel(features[1])
plt.title('Customer Segments')
plt.colorbar(scatter)
plt.show()

# Print cluster statistics with better formatting
print("\nCluster Statistics Summary:")
print("==========================")
for cluster in range(optimal_k):
    print(f"\nCluster {cluster} - Size: {len(df[df['Cluster'] == cluster])} customers")
    print("-" * 50)
    cluster_data = df[df['Cluster'] == cluster]
    
    # Calculate mean values for each feature
    means = cluster_data[features].mean()
    
    # Print interpretable statistics
    print("Average characteristics:")
    print(f"• Days Since Last Visit: {means['DaysSinceLastVisit']:.1f} days")
    print(f"• Customer Tenure: {means['CustomerTenureDays']:.1f} days")
    print(f"• Basket Diversity: {means['BasketDiversity']:.2f}")
    print(f"• Average Spend Per Visit: ${means['AvgSpendPerVisit']:.2f}")
    print(f"• Average Days between visits: {means['AvgDaysBetweenVisits']:.2f}")
    print(f"• Tolal Spend: ${sum['TtlSpend']:.2f}")
    print(f"• Last three Months Growth Rate: {means['Last3MonthsGrowthRatio']:.2f}")
    print(f"• Last six Months Growth Rate: {means['Last6MonthsGrowthRatio']:.2f}")
    print(f"• Last three Months Visit Growth Rate: {means['Last3MonthsVisitsGrowthRatio']:.2f}")

# Calculate feature importance using cluster centroids
feature_importance = pd.DataFrame(
    scaler.inverse_transform(kmeans.cluster_centers_),
    columns=features
)

print("\nFeature Ranges Across Clusters:")
print("==============================")
for feature in features:
    feature_range = feature_importance[feature].max() - feature_importance[feature].min()
    print(f"• {feature}: {feature_range:.2f}")

# Save results
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
output_path = os.path.join(current_dir, f'Customer Data Segments_{timestamp}.csv')
df.to_csv(output_path, index=False)
print(f"\nResults saved to: {output_path}")