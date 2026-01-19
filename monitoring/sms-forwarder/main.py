#!/usr/bin/env python3
"""
短信转发服务 - 接收 AlertManager Webhook 并发送短信通知

支持阿里云短信和腾讯云短信 API
"""

import os
import json
import logging
from datetime import datetime
from flask import Flask, request, jsonify

# 阿里云短信 SDK
try:
    from aliyunsdkcore.client import AcsClient
    from aliyunsdkcore.request import CommonRequest
    ALIYUN_AVAILABLE = True
except ImportError:
    ALIYUN_AVAILABLE = False
    logging.warning("阿里云 SDK 未安装,短信功能将不可用")

app = Flask(__name__)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 环境变量配置
ALIYUN_ACCESS_KEY = os.getenv('ALIYUN_ACCESS_KEY', '')
ALIYUN_ACCESS_SECRET = os.getenv('ALIYUN_ACCESS_SECRET', '')
ALIYUN_SMS_SIGN = os.getenv('ALIYUN_SMS_SIGN', '')
ALIYUN_SMS_TEMPLATE = os.getenv('ALIYUN_SMS_TEMPLATE', '')
ALERT_PHONE = os.getenv('ALERT_PHONE', '')

# 初始化阿里云客户端
aliyun_client = None
if ALIYUN_AVAILABLE and ALIYUN_ACCESS_KEY and ALIYUN_ACCESS_SECRET:
    aliyun_client = AcsClient(ALIYUN_ACCESS_KEY, ALIYUN_ACCESS_SECRET, 'cn-hangzhou')
    logger.info("阿里云短信客户端初始化成功")
else:
    logger.warning("阿里云短信客户端未配置")


def send_aliyun_sms(phone, template_param):
    """
    发送阿里云短信

    Args:
        phone: 手机号
        template_param: 模板参数字典

    Returns:
        bool: 发送是否成功
    """
    if not aliyun_client:
        logger.error("阿里云客户端未初始化")
        return False

    try:
        request = CommonRequest()
        request.set_accept_format('json')
        request.set_domain('dysmsapi.aliyuncs.com')
        request.set_method('POST')
        request.set_protocol_type('https')
        request.set_version('2017-05-25')
        request.set_action_name('SendSms')

        request.add_query_param('PhoneNumbers', phone)
        request.add_query_param('SignName', ALIYUN_SMS_SIGN)
        request.add_query_param('TemplateCode', ALIYUN_SMS_TEMPLATE)
        request.add_query_param('TemplateParam', json.dumps(template_param))

        response = aliyun_client.do_action_with_exception(request)
        result = json.loads(response)

        if result.get('Code') == 'OK':
            logger.info(f"短信发送成功: {phone}")
            return True
        else:
            logger.error(f"短信发送失败: {result.get('Message')}")
            return False

    except Exception as e:
        logger.error(f"短信发送异常: {str(e)}")
        return False


def parse_alertmanager_payload(payload):
    """
    解析 AlertManager webhook payload

    Args:
        payload: AlertManager 发送的 JSON 数据

    Returns:
        dict: 解析后的告警信息
    """
    alerts = payload.get('alerts', [])
    status = payload.get('status', 'unknown')

    # 提取第一个告警的关键信息
    if alerts:
        alert = alerts[0]
        labels = alert.get('labels', {})
        annotations = alert.get('annotations', {})

        return {
            'status': status,
            'alertname': labels.get('alertname', 'Unknown'),
            'severity': labels.get('severity', 'unknown'),
            'instance': labels.get('instance', 'unknown'),
            'summary': annotations.get('summary', ''),
            'description': annotations.get('description', ''),
            'count': len(alerts)
        }

    return {
        'status': status,
        'alertname': 'Unknown',
        'severity': 'unknown',
        'instance': 'unknown',
        'summary': '',
        'description': '',
        'count': 0
    }


@app.route('/health', methods=['GET'])
def health_check():
    """健康检查端点"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'aliyun_configured': aliyun_client is not None
    })


@app.route('/webhook/sms', methods=['POST'])
def webhook_sms():
    """
    接收 AlertManager webhook 并发送短信

    只处理 firing 状态的告警,resolved 不发送短信
    """
    try:
        payload = request.get_json()
        logger.info(f"收到 webhook 请求: {payload.get('status')}")

        # 解析告警信息
        alert_info = parse_alertmanager_payload(payload)

        # 只处理 firing 状态的告警
        if alert_info['status'] != 'firing':
            logger.info("告警已恢复,跳过短信发送")
            return jsonify({'status': 'skipped', 'reason': 'resolved'})

        # 只处理 critical 级别的告警
        if alert_info['severity'] != 'critical':
            logger.info(f"告警级别为 {alert_info['severity']},跳过短信发送")
            return jsonify({'status': 'skipped', 'reason': 'not_critical'})

        # 构造短信模板参数
        # 根据你的阿里云短信模板调整参数
        template_param = {
            'alertname': alert_info['alertname'],
            'instance': alert_info['instance'],
            'summary': alert_info['summary'][:50]  # 限制长度
        }

        # 发送短信
        success = send_aliyun_sms(ALERT_PHONE, template_param)

        if success:
            return jsonify({
                'status': 'success',
                'message': '短信发送成功',
                'alert': alert_info
            })
        else:
            return jsonify({
                'status': 'failed',
                'message': '短信发送失败',
                'alert': alert_info
            }), 500

    except Exception as e:
        logger.error(f"处理 webhook 异常: {str(e)}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500


@app.route('/webhook/default', methods=['POST'])
def webhook_default():
    """默认 webhook 端点,仅记录日志"""
    try:
        payload = request.get_json()
        alert_info = parse_alertmanager_payload(payload)
        logger.info(f"收到默认 webhook: {alert_info}")

        return jsonify({
            'status': 'logged',
            'alert': alert_info
        })

    except Exception as e:
        logger.error(f"处理默认 webhook 异常: {str(e)}")
        return jsonify({
            'status': 'error',
            'message': str(e)
        }), 500


if __name__ == '__main__':
    # 检查必要的环境变量
    if not ALERT_PHONE:
        logger.warning("未配置 ALERT_PHONE 环境变量")

    if not all([ALIYUN_ACCESS_KEY, ALIYUN_ACCESS_SECRET, ALIYUN_SMS_SIGN, ALIYUN_SMS_TEMPLATE]):
        logger.warning("阿里云短信配置不完整,短信功能将不可用")

    # 启动 Flask 应用
    app.run(host='0.0.0.0', port=5000, debug=False)
