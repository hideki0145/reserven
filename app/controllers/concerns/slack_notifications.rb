module SlackNotifications
  private

  def notify_slack(payload)
    return unless SlackNotifier.deliver(payload) == false

    flash[:alert] = '操作は保存されましたが、Slack通知を送信できませんでした。同じ操作を繰り返さず、管理者にお問い合わせください。'
  end
end
