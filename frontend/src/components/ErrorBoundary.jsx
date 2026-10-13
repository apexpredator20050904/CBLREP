// ---------------------------------------------------------------------------
// CBLRE Admin · React Error Boundary
// ---------------------------------------------------------------------------
// Catches unhandled errors in any child route/tab and renders a friendly
// fallback with a Retry button instead of a blank white screen.
// ---------------------------------------------------------------------------
import { Component } from "react";

export default class ErrorBoundary extends Component {
  state = { hasError: false, error: null, errorInfo: null };

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    this.setState({ errorInfo });
    console.error("[ErrorBoundary] crashed:", error, errorInfo?.componentStack);
  }

  handleRetry = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="m-6">
          <div className="mx-auto max-w-lg rounded-2xl border border-stone-200 bg-white p-6 shadow-lg">
            <div className="flex items-start gap-3">
              <div className="mt-0.5 flex h-9 w-9 flex-none items-center justify-center rounded-full bg-red-100 text-red-700">!
              </div>
              <div className="flex-1">
                <h2 className="text-lg font-bold text-emerald-950">Something went wrong</h2>
                <p className="mt-1 text-sm text-stone-600">
                  {this.state.error?.toString() ?? "An unexpected error occurred in this tab."}
                </p>
                {this.state.errorInfo?.componentStack && (
                  <pre className="mt-2 max-h-40 overflow-auto text-xs text-stone-500">
                    {this.state.errorInfo.componentStack}
                  </pre>
                )}
              </div>
            </div>
            <div className="mt-4 flex justify-end">
              <button
                type="button"
                onClick={this.handleRetry}
                className="rounded-lg border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-emerald-950 hover:bg-stone-50"
              >
                Retry
              </button>
            </div>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
