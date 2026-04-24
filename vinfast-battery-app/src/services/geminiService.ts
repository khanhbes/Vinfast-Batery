import { GoogleGenAI, Type } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

export async function predictBatteryConsumption(
  distance: number,
  weight: number,
  weather: string,
  temp: number
): Promise<{ consumption: number; reasoning: string }> {
  try {
    const response = await ai.models.generateContent({
      model: "gemini-3-flash-preview",
      contents: `Predict battery consumption for a VinFast Feliz Neo electric scooter.
      Distance: ${distance} km
      Rider Weight: ${weight} kg
      Weather: ${weather}
      Temperature: ${temp}°C
      
      Return the predicted consumption in percentage (%) and a brief reasoning.`,
      config: {
        responseMimeType: "application/json",
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            consumption: { type: Type.NUMBER, description: "Predicted battery percentage consumption" },
            reasoning: { type: Type.STRING, description: "Brief explanation of the prediction" }
          },
          required: ["consumption", "reasoning"]
        }
      }
    });

    const result = JSON.parse(response.text || "{}");
    return {
      consumption: result.consumption || (distance * 0.8), // Fallback heuristic
      reasoning: result.reasoning || "Based on average consumption rates."
    };
  } catch (error) {
    console.error("AI Prediction Error:", error);
    return {
      consumption: distance * 0.8,
      reasoning: "Heuristic prediction due to AI service unavailability."
    };
  }
}
