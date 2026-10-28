import { Component, type ErrorInfo, type ReactNode } from 'react'
import { Button } from '@/components/ui/button'

/**
 * ErrorBoundary：捕获子组件渲染异常，避免整个页面白屏。
 * 显示友好错误提示并提供刷新按钮。
 */
type Props = {
  children: ReactNode
}

type State = {
  hasError: boolean
  error: Error | null
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    console.error('页面渲染异常：', error, errorInfo)
  }

  handleReload = () => {
    window.location.reload()
  }

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex min-h-[60vh] flex-col items-center justify-center gap-4 p-8">
          <h2 className="text-lg font-semibold">页面出现异常</h2>
          <p className="text-sm text-muted-foreground">
            {this.state.error?.message ?? '未知错误，请刷新页面重试'}
          </p>
          <Button onClick={this.handleReload}>刷新页面</Button>
        </div>
      )
    }
    return this.props.children
  }
}
