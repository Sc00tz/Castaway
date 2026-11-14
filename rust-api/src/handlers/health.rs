use axum::{extract::State, response::Json};
use chrono::Utc;
use crate::{
    error::AppResult,
    models::{CastawayCheckResponse, HealthResponse},
    AppState,
};

/// Lets apps confirm the address they were given is a Castaway server.
/// GET /api/castaway_check
#[utoipa::path(
    get,
    path = "/api/castaway_check",
    tag = "health",
    responses(
        (status = 200, description = "Confirms this is a Castaway instance", body = CastawayCheckResponse),
    ),
)]
pub async fn castaway_check() -> Json<CastawayCheckResponse> {
    Json(CastawayCheckResponse {
        status_code: 200,
        castaway_instance: true,
    })
}

/// Health check endpoint with database and Redis status
/// GET /api/health
#[utoipa::path(
    get,
    path = "/api/health",
    tag = "health",
    responses(
        (status = 200, description = "Database and Redis connectivity status", body = HealthResponse),
        (status = 500, description = "Service is unhealthy"),
    ),
)]
pub async fn health_check(State(state): State<AppState>) -> AppResult<Json<HealthResponse>> {
    // Check database health
    let database_healthy = state.db_pool.health_check().await.unwrap_or(false);
    
    // Check Redis health
    let redis_healthy = state.redis_client.health_check().await.unwrap_or(false);
    
    let overall_status = if database_healthy && redis_healthy {
        "healthy"
    } else {
        "unhealthy"
    };

    Ok(Json(HealthResponse {
        status: overall_status.to_string(),
        database: database_healthy,
        redis: redis_healthy,
        timestamp: Utc::now(),
    }))
}