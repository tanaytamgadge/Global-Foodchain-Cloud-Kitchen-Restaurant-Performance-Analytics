-- 1. Top Selling Item by Revenue (Top 10 Products Globally)
SELECT Product_ID, Product_Name, Product_Category, SUM(Revenue_Generated) AS Total_Revenue
FROM Sales
GROUP BY Product_ID, Product_Name, Product_Category
ORDER BY Total_Revenue DESC
LIMIT 10;

-- 2. Average Sales per Product Category (Grouped by Category)
SELECT Product_Category, AVG(Sales_Amount) AS Average_Sales
FROM Sales
GROUP BY Product_Category
ORDER BY Average_Sales DESC;

-- 3. Best Performing Ingredients (Most Popular Ingredients)
SELECT Ingredient_Name, COUNT(*) AS Ingredient_Count
FROM Product_Ingredients
GROUP BY Ingredient_Name
ORDER BY Ingredient_Count DESC
LIMIT 5;

-- 4. Best Selling Products in the Last Month (Monthly Performance)
SELECT Product_ID, Product_Name, SUM(Sales_Amount) AS Monthly_Sales
FROM Sales
WHERE Sale_Date >= CURDATE() - INTERVAL 1 MONTH
GROUP BY Product_ID, Product_Name
ORDER BY Monthly_Sales DESC;

-- 5. Total Revenue and Sales per Employee (Employee Sales Performance)
SELECT Employee_ID, Employee_Name, SUM(Sales_Amount) AS Total_Sales, COUNT(Order_ID) AS Total_Orders
FROM Sales
JOIN Employees ON Sales.Employee_ID = Employees.Employee_ID
GROUP BY Employee_ID, Employee_Name
ORDER BY Total_Sales DESC;

-- 6. Correlation Between Product Price and Sales (Price vs Sales Analysis)
WITH PriceStats AS (
    SELECT AVG(Product_Price) AS avg_price, STDDEV(Product_Price) AS price_stddev
    FROM Products
)
SELECT p.Product_ID, p.Product_Name, p.Product_Price, SUM(s.Sales_Amount) AS Total_Sales,
       (SUM(s.Sales_Amount) - AVG(s.Sales_Amount)) / PriceStats.price_stddev AS Price_Sales_Correlation
FROM Sales s
JOIN Products p ON s.Product_ID = p.Product_ID
JOIN PriceStats
GROUP BY p.Product_ID, p.Product_Name, p.Product_Price;

-- 7. Low Sales Products in the Last 3 Months (Underperforming Items)
SELECT Product_ID, Product_Name, SUM(Sales_Amount) AS Total_Sales
FROM Sales
WHERE Sale_Date >= CURDATE() - INTERVAL 3 MONTH
GROUP BY Product_ID, Product_Name
HAVING Total_Sales < 1000
ORDER BY Total_Sales ASC;

-- 8. Customer Spending Habits (Average Spend per Customer)
SELECT Customer_ID, AVG(Total_Spend) AS Average_Spend
FROM Orders
GROUP BY Customer_ID
ORDER BY Average_Spend DESC;

-- 9. High-Volume Product Orders per Day (Most Ordered Items)
SELECT Product_ID, Product_Name, COUNT(Order_ID) AS Order_Count
FROM Sales
GROUP BY Product_ID, Product_Name
ORDER BY Order_Count DESC
LIMIT 5;

-- 10. Revenue Growth by Product Category (Month-over-Month Analysis)
SELECT Product_Category, 
       EXTRACT(YEAR FROM Sale_Date) AS Year, 
       EXTRACT(MONTH FROM Sale_Date) AS Month,
       SUM(Sales_Amount) AS Monthly_Revenue,
       LAG(SUM(Sales_Amount)) OVER (PARTITION BY Product_Category ORDER BY EXTRACT(YEAR FROM Sale_Date), EXTRACT(MONTH FROM Sale_Date)) AS Previous_Month_Revenue,
       (SUM(Sales_Amount) - 
        LAG(SUM(Sales_Amount)) OVER (PARTITION BY Product_Category ORDER BY EXTRACT(YEAR FROM Sale_Date), EXTRACT(MONTH FROM Sale_Date))) / 
       LAG(SUM(Sales_Amount)) OVER (PARTITION BY Product_Category ORDER BY EXTRACT(YEAR FROM Sale_Date), EXTRACT(MONTH FROM Sale_Date)) * 100 AS Revenue_Growth_Percentage
FROM Sales
GROUP BY Product_Category, EXTRACT(YEAR FROM Sale_Date), EXTRACT(MONTH FROM Sale_Date)
ORDER BY Product_Category, Year, Month;

-- 11. Total Sales vs. Product Category Revenue Share (Revenue Share by Category)
WITH Category_Revenue AS (
    SELECT Product_Category, SUM(Sales_Amount) AS Total_Category_Revenue
    FROM Sales
    GROUP BY Product_Category
)
SELECT s.Product_ID, s.Product_Name, s.Product_Category, SUM(s.Sales_Amount) AS Total_Product_Revenue,
       (SUM(s.Sales_Amount) / cr.Total_Category_Revenue) * 100 AS Product_Revenue_Percentage
FROM Sales s
JOIN Category_Revenue cr ON s.Product_Category = cr.Product_Category
GROUP BY s.Product_ID, s.Product_Name, s.Product_Category
ORDER BY Product_Revenue_Percentage DESC;

-- 12. Best Performing Employee Based on Revenue (Top Revenue Generating Employees)
SELECT Employee_ID, Employee_Name, SUM(Sales_Amount) AS Total_Sales
FROM Sales
JOIN Employees ON Sales.Employee_ID = Employees.Employee_ID
GROUP BY Employee_ID, Employee_Name
ORDER BY Total_Sales DESC
LIMIT 1;

-- 13. Product Sales by Time of Day (Sales Pattern Analysis by Time)
SELECT Product_ID, Product_Name, 
       EXTRACT(HOUR FROM Sale_Time) AS Sale_Hour,
       SUM(Sales_Amount) AS Total_Sales
FROM Sales
GROUP BY Product_ID, Product_Name, EXTRACT(HOUR FROM Sale_Time)
ORDER BY Total_Sales DESC;

-- 14. Customer Retention Rate (Repeat Customer Analysis)
SELECT Customer_ID, COUNT(DISTINCT Order_ID) AS Total_Orders, 
       COUNT(DISTINCT CASE WHEN Order_Date > CURDATE() - INTERVAL 1 MONTH THEN Order_ID END) AS Recent_Orders
FROM Orders
GROUP BY Customer_ID
HAVING Recent_Orders > 1;

-- 15. Product Order Distribution by Day of the Week (Day-of-Week Trends)
SELECT Product_ID, Product_Name, 
       EXTRACT(DAYOFWEEK FROM Sale_Date) AS Day_Of_Week, 
       COUNT(Order_ID) AS Total_Orders
FROM Sales
GROUP BY Product_ID, Product_Name, EXTRACT(DAYOFWEEK FROM Sale_Date)
ORDER BY Total_Orders DESC;

-- 16. Products with Discounts Applied (Discount Impact on Sales)
SELECT Product_ID, Product_Name, SUM(Sales_Amount) AS Total_Sales, SUM(Discount_Amount) AS Total_Discounts
FROM Sales
WHERE Discount_Amount > 0
GROUP BY Product_ID, Product_Name
ORDER BY Total_Sales DESC;

-- 17. Average Order Size per Customer (Orders per Customer)
SELECT Customer_ID, AVG(Order_Size) AS Average_Order_Size
FROM Orders
GROUP BY Customer_ID
ORDER BY Average_Order_Size DESC;

-- 18. Most Profitable Products Based on Revenue and Margin (Profit Margin Analysis)
SELECT p.Product_ID, p.Product_Name, SUM(s.Sales_Amount) AS Total_Revenue,
       (SUM(s.Sales_Amount) - SUM(p.Product_Cost)) AS Total_Profit
FROM Sales s
JOIN Products p ON s.Product_ID = p.Product_ID
GROUP BY p.Product_ID, p.Product_Name
ORDER BY Total_Profit DESC
LIMIT 5;

-- 19. Best Customer Segments by Purchase Frequency (Customer Segmentation)
SELECT Customer_Segment, COUNT(DISTINCT Order_ID) AS Total_Orders
FROM Orders
JOIN Customers ON Orders.Customer_ID = Customers.Customer_ID
GROUP BY Customer_Segment
ORDER BY Total_Orders DESC;

-- 20. Sales Performance Before and After Promotion (Promotional Impact)
SELECT p.Product_ID, p.Product_Name,
       SUM(CASE WHEN Sale_Date < '2025-01-01' THEN Sales_Amount ELSE 0 END) AS Pre_Promotion_Sales,
       SUM(CASE WHEN Sale_Date >= '2025-01-01' THEN Sales_Amount ELSE 0 END) AS Post_Promotion_Sales
FROM Sales s
JOIN Products p ON s.Product_ID = p.Product_ID
GROUP BY p.Product_ID, p.Product_Name
ORDER BY Post_Promotion_Sales DESC;

-- 21. Employee Performance Based on Tips (Employee Efficiency with Tips)
SELECT Employee_ID, Employee_Name, SUM(Tip_Amount) AS Total_Tips
FROM Sales
JOIN Employees ON Sales.Employee_ID = Employees.Employee_ID
GROUP BY Employee_ID, Employee_Name
ORDER BY Total_Tips DESC;

-- 22. Product Sales and Delivery Times (Product Delivery Time Analysis)
SELECT Product_ID, Product_Name, AVG(TIMESTAMPDIFF(MINUTE, Order_Time, Delivery_Time)) AS Average_Delivery_Time
FROM Sales
GROUP BY Product_ID, Product_Name
ORDER BY Average_Delivery_Time ASC;

-- 23. Customer Feedback Analysis (Product Rating vs Sales)
SELECT Product_ID, Product_Name, AVG(Customer_Rating) AS Average_Rating
FROM Sales
GROUP BY Product_ID, Product_Name
ORDER BY Average_Rating DESC;

-- 24. Highest Revenue by Ingredient Combination (Revenue from Ingredient Mix)
SELECT Ingredient_Name, SUM(Sales_Amount) AS Total_Revenue
FROM Product_Ingredients
JOIN Sales ON Product_Ingredients.Product_ID = Sales.Product_ID
GROUP BY Ingredient_Name
ORDER BY Total_Revenue DESC;

-- 25. Product Price and Sales Relationship (Price Sensitivity Analysis)
SELECT Product_Price, SUM(Sales_Amount) AS Total_Revenue
FROM Sales s
JOIN Products p ON s.Product_ID = p.Product_ID
GROUP BY Product_Price
ORDER BY Total_Revenue DESC;

-- 26. Total Revenue and Profit by Product Category (Category Profitability)
WITH Category_Profit AS (
    SELECT Product_Category, 
           SUM(Sales_Amount) AS Total_Revenue, 
           SUM(Product_Cost) AS Total_Cost
    FROM Sales s
    JOIN Products p ON s.Product_ID = p.Product_ID
    GROUP BY Product_Category
)
SELECT Product_Category, 
       Total_Revenue, 
       Total_Cost, 
       Total_Revenue - Total_Cost AS Profit
FROM Category_Profit
ORDER BY Profit DESC;

-- 27. Sales per Square Foot by Location (Location Efficiency)
SELECT Store_Location, SUM(Sales_Amount) AS Total_Sales, 
       (SUM(Sales_Amount) / Store_Square_Footage) AS Sales_Per_Square_Foot
FROM Sales s
JOIN Stores st ON s.Store_ID = st.Store_ID
GROUP BY Store_Location
ORDER BY Sales_Per_Square_Foot DESC;

-- 28. Promotional Discounts and Sales Effectiveness (Impact of Discounts)
SELECT Promotion_ID, SUM(Sales_Amount) AS Total_Sales
FROM Sales
WHERE Promotion_ID IS NOT NULL
GROUP BY Promotion_ID
ORDER BY Total_Sales DESC;

-- 29. Product Order Fulfillment Time (Order Completion Time)
SELECT Product_ID, Product_Name, AVG(TIMESTAMPDIFF(MINUTE, Order_Time, Fulfillment_Time)) AS Average_Fulfillment_Time
FROM Sales
GROUP BY Product_ID, Product_Name
ORDER BY Average_Fulfillment_Time DESC;

-- 30. Monthly Product Revenue Trends (Revenue Trend Analysis)
SELECT EXTRACT(YEAR FROM Sale_Date) AS Year, 
       EXTRACT(MONTH FROM Sale_Date) AS Month, 
       SUM(Sales_Amount) AS Monthly_Revenue
FROM Sales
GROUP BY EXTRACT(YEAR FROM Sale_Date), EXTRACT(MONTH FROM Sale_Date)
ORDER BY Year DESC, Month DESC;
